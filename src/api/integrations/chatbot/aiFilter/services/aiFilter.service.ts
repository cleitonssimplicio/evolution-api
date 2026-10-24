/* eslint-disable @typescript-eslint/no-unused-vars */
import { PrismaRepository } from '@api/repository/repository.service';
import { WAMonitoringService } from '@api/services/monitor.service';
import { ConfigService } from '@config/env.config';
import { AiFilterBot, AiFilterSetting, IntegrationSession } from '@prisma/client';
import { sendTelemetry } from '@utils/sendTelemetry';
import OpenAI from 'openai';

import { BaseChatbotService } from '../../base-chatbot.service';
import { AiFilterCategory } from '../dto/aiFilter.dto';

interface ClassificationResult {
  category: string;
  action: 'auto_respond' | 'flag_human' | 'ignore';
  response?: string;
}

export class AiFilterService extends BaseChatbotService<AiFilterBot, AiFilterSetting> {
  private client: OpenAI;

  constructor(waMonitor: WAMonitoringService, prismaRepository: PrismaRepository, configService: ConfigService) {
    super(waMonitor, prismaRepository, 'AiFilterService', configService);
  }

  protected getBotType(): string {
    return 'aiFilter';
  }

  /**
   * Aceita qualquer endpoint compativel com a API da OpenAI, o que permite usar
   * provedores com plano gratuito (Groq, Gemini, OpenRouter, Ollama) sem
   * nenhuma alteracao de codigo - basta configurar apiBaseUrl no bot.
   */
  private initClient(apiKey: string, apiBaseUrl?: string | null): void {
    this.client = new OpenAI({
      apiKey,
      baseURL: apiBaseUrl?.trim() || undefined,
    });
  }

  /**
   * Modelos abertos costumam devolver o JSON embrulhado em bloco markdown ou
   * cercado de texto. Extrai o objeto JSON de forma tolerante.
   */
  private parseJsonLoose(raw: string): any {
    const cleaned = raw
      .trim()
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/```$/, '')
      .trim();

    try {
      return JSON.parse(cleaned);
    } catch {
      const start = cleaned.indexOf('{');
      const end = cleaned.lastIndexOf('}');
      if (start !== -1 && end > start) {
        return JSON.parse(cleaned.slice(start, end + 1));
      }
      throw new Error('no JSON object found');
    }
  }

  /**
   * Nem todo provedor gratuito suporta response_format json_object. Tenta com
   * o modo JSON e, se o provedor recusar, repete sem ele.
   */
  private async createCompletion(params: any, useJsonMode: boolean): Promise<string> {
    try {
      const completion = await this.client.chat.completions.create(
        useJsonMode ? { ...params, response_format: { type: 'json_object' } } : params,
      );
      return completion.choices[0]?.message?.content || '';
    } catch (error: any) {
      if (useJsonMode) {
        this.logger.warn(`Provider rejected json_object mode, retrying without it: ${error?.message || error}`);
        const completion = await this.client.chat.completions.create(params);
        return completion.choices[0]?.message?.content || '';
      }
      throw error;
    }
  }

  private buildClassificationPrompt(filterCategories: AiFilterCategory[], systemPrompt?: string): string {
    const categoriesDescription = filterCategories
      .map((cat, idx) => `${idx + 1}. "${cat.name}": ${cat.description} → action: ${cat.action}`)
      .join('\n');

    const categoryNames = filterCategories.map((c) => `"${c.name}"`).join(', ');

    return `${systemPrompt || 'You are an intelligent WhatsApp message classifier.'}

Classify the incoming message into one of these categories:

${categoriesDescription}

Return ONLY a valid JSON object with this structure:
{
  "category": <one of: ${categoryNames}>,
  "action": <"auto_respond" | "flag_human" | "ignore">,
  "response": <string with your response if action is "auto_respond", otherwise null>
}

Rules:
- Match the action defined for each category above
- If action is "auto_respond", write a helpful response in the same language as the message
- If action is "flag_human" or "ignore", set response to null
- Return ONLY valid JSON, no additional text`;
  }

  private async classifyMessage(
    content: string,
    filterCategories: AiFilterCategory[],
    model: string,
    systemPrompt?: string,
    pushName?: string,
  ): Promise<ClassificationResult> {
    const classificationSystem = this.buildClassificationPrompt(filterCategories, systemPrompt);
    const userMessage = pushName ? `From ${pushName}: ${content}` : content;

    const rawResult = await this.createCompletion(
      {
        model,
        messages: [
          { role: 'system', content: classificationSystem },
          { role: 'user', content: userMessage },
        ],
        temperature: 0.2,
        max_tokens: 800,
      },
      true,
    );

    try {
      const parsed = this.parseJsonLoose(rawResult) as ClassificationResult;
      const validActions: Array<'auto_respond' | 'flag_human' | 'ignore'> = ['auto_respond', 'flag_human', 'ignore'];
      if (!parsed.action || !validActions.includes(parsed.action)) {
        parsed.action = 'flag_human';
      }
      return parsed;
    } catch {
      this.logger.error(`Failed to parse AI classification: ${rawResult}`);
      return { category: 'unknown', action: 'flag_human' };
    }
  }

  private async generateFallbackResponse(
    content: string,
    model: string,
    autoRespondPrompt?: string,
    matchedCategory?: AiFilterCategory,
    pushName?: string,
  ): Promise<string> {
    const system =
      autoRespondPrompt || 'You are a helpful WhatsApp assistant. Respond naturally in the same language as the user.';

    const messages: Array<{ role: 'system' | 'user'; content: string }> = [{ role: 'system', content: system }];

    if (matchedCategory?.responseTemplate) {
      messages.push({ role: 'system', content: `Response template: ${matchedCategory.responseTemplate}` });
    }

    messages.push({ role: 'user', content: pushName ? `${pushName}: ${content}` : content });

    return this.createCompletion({ model, messages, temperature: 0.7, max_tokens: 500 }, false);
  }

  public async process(
    instance: any,
    remoteJid: string,
    bot: AiFilterBot,
    session: IntegrationSession,
    settings: AiFilterSetting,
    content: string,
    pushName?: string,
    msg?: any,
  ): Promise<void> {
    try {
      this.logger.log(`AiFilter processing message from ${remoteJid}`);

      const keywordFinish = settings?.keywordFinish || '';
      if (keywordFinish.length > 0 && content.toLowerCase().trim() === keywordFinish.toLowerCase()) {
        if (settings?.keepOpen) {
          await this.prismaRepository.integrationSession.update({
            where: { id: session.id },
            data: { status: 'closed' },
          });
        } else {
          await this.prismaRepository.integrationSession.delete({ where: { id: session.id } });
        }
        await sendTelemetry('/aiFilter/session/finish');
        return;
      }

      if (!session) {
        const data = { remoteJid, pushName, botId: bot.id };
        const createSession = await this.createNewSession(
          { instanceName: instance.instanceName, instanceId: instance.instanceId },
          data,
          this.getBotType(),
        );

        await this.initNewSession(instance, remoteJid, bot, settings, createSession.session, content, pushName, msg);
        await sendTelemetry('/aiFilter/session/start');
        return;
      }

      if (session.status === 'paused') {
        return;
      }

      await this.sendMessageToBot(instance, session, settings, bot, remoteJid, pushName || '', content, msg);
    } catch (error) {
      this.logger.error(`AiFilter process error: ${error}`);
    }
  }

  protected async sendMessageToBot(
    instance: any,
    session: IntegrationSession,
    settings: AiFilterSetting,
    bot: AiFilterBot,
    remoteJid: string,
    pushName: string,
    content: string,
    _msg?: any,
  ): Promise<void> {
    try {
      const creds = await this.prismaRepository.openaiCreds.findUnique({
        where: { id: bot.openaiCredsId },
      });

      if (!creds) {
        this.logger.error(`OpenAI credentials not found. CredsId: ${bot.openaiCredsId}`);
        return;
      }

      this.initClient(creds.apiKey, bot.apiBaseUrl);

      const filterCategories: AiFilterCategory[] = Array.isArray(bot.filterCategories)
        ? (bot.filterCategories as unknown as AiFilterCategory[])
        : [];

      if (filterCategories.length === 0) {
        this.logger.warn(`AiFilter bot ${bot.id} has no filter categories configured`);
        return;
      }

      const model = bot.model || 'gpt-4o-mini';

      const classification = await this.classifyMessage(
        content,
        filterCategories,
        model,
        bot.systemPrompt || undefined,
        pushName,
      );

      this.logger.log(`Classified as: ${classification.category} → ${classification.action}`);
      await sendTelemetry('/aiFilter/message/classified');

      if (classification.action === 'ignore') {
        return;
      }

      if (classification.action === 'flag_human') {
        await this.prismaRepository.integrationSession.update({
          where: { id: session.id },
          data: { status: 'paused' },
        });

        const unknownMsg = settings?.unknownMessage;
        if (unknownMsg) {
          await this.sendMessageWhatsApp(instance, remoteJid, unknownMsg, settings, true);
        }
        return;
      }

      if (classification.action === 'auto_respond') {
        let responseText = classification.response;
        const matchedCategory = filterCategories.find((c) => c.name === classification.category);

        if (!responseText?.trim()) {
          responseText = await this.generateFallbackResponse(
            content,
            model,
            bot.autoRespondPrompt || undefined,
            matchedCategory,
            pushName,
          );
        }

        if (responseText) {
          await this.sendMessageWhatsApp(instance, remoteJid, responseText, settings, true);
        }
      }
    } catch (error) {
      this.logger.error(`AiFilter sendMessageToBot error: ${error}`);
      throw error;
    }
  }
}
