import { PrismaRepository } from '@api/repository/repository.service';
import { WAMonitoringService } from '@api/services/monitor.service';
import { Logger } from '@config/logger.config';
import { AiFilterBot, IntegrationSession } from '@prisma/client';

import { BaseChatbotController } from '../../base-chatbot.controller';
import { AiFilterDto } from '../dto/aiFilter.dto';
import { AiFilterService } from '../services/aiFilter.service';

export class AiFilterController extends BaseChatbotController<AiFilterBot, AiFilterDto> {
  constructor(
    private readonly aiFilterService: AiFilterService,
    prismaRepository: PrismaRepository,
    waMonitor: WAMonitoringService,
  ) {
    super(prismaRepository, waMonitor);

    this.botRepository = this.prismaRepository.aiFilterBot;
    this.settingsRepository = this.prismaRepository.aiFilterSetting;
    this.sessionRepository = this.prismaRepository.integrationSession;
  }

  public readonly logger = new Logger('AiFilterController');
  protected readonly integrationName = 'AiFilter';

  integrationEnabled = true;
  botRepository: any;
  settingsRepository: any;
  sessionRepository: any;
  userMessageDebounce: { [key: string]: { message: string; timeoutId: NodeJS.Timeout } } = {};

  protected getFallbackBotId(settings: any): string | undefined {
    return settings?.botIdFallback;
  }

  protected getFallbackFieldName(): string {
    return 'botIdFallback';
  }

  protected getIntegrationType(): string {
    return 'aiFilter';
  }

  protected getAdditionalBotData(data: AiFilterDto): Record<string, any> {
    return {
      openaiCredsId: data.openaiCredsId,
      model: data.model,
      systemPrompt: data.systemPrompt,
      filterCategories: data.filterCategories,
      autoRespondPrompt: data.autoRespondPrompt,
    };
  }

  protected getAdditionalUpdateFields(data: AiFilterDto): Record<string, any> {
    return {
      openaiCredsId: data.openaiCredsId,
      model: data.model,
      systemPrompt: data.systemPrompt,
      filterCategories: data.filterCategories,
      autoRespondPrompt: data.autoRespondPrompt,
    };
  }

  protected async validateNoDuplicatesOnUpdate(botId: string, instanceId: string, data: AiFilterDto): Promise<void> {
    const checkDuplicate = await this.botRepository.findFirst({
      where: {
        id: { not: botId },
        instanceId,
        openaiCredsId: data.openaiCredsId,
        triggerType: data.triggerType,
        triggerValue: data.triggerValue,
      },
    });

    if (checkDuplicate) {
      throw new Error('AiFilter bot with same configuration already exists');
    }
  }

  protected async processBot(
    instance: any,
    remoteJid: string,
    bot: AiFilterBot,
    session: IntegrationSession,
    settings: any,
    content: string,
    pushName?: string,
    msg?: any,
  ) {
    await this.aiFilterService.process(instance, remoteJid, bot, session, settings, content, pushName, msg);
  }
}
