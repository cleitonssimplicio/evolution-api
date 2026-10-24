import { BaseChatbotDto, BaseChatbotSettingDto } from '../../base-chatbot.dto';

export interface AiFilterCategory {
  name: string;
  description: string;
  action: 'auto_respond' | 'flag_human' | 'ignore';
  responseTemplate?: string;
}

export class AiFilterDto extends BaseChatbotDto {
  openaiCredsId: string;
  model?: string;
  /**
   * Endpoint compativel com a API da OpenAI. Deixe vazio para usar a propria
   * OpenAI, ou aponte para um provedor com plano gratuito, por exemplo:
   *   Groq       -> https://api.groq.com/openai/v1
   *   Gemini     -> https://generativelanguage.googleapis.com/v1beta/openai
   *   OpenRouter -> https://openrouter.ai/api/v1
   *   Ollama     -> http://localhost:11434/v1
   */
  apiBaseUrl?: string;
  systemPrompt?: string;
  filterCategories?: AiFilterCategory[];
  autoRespondPrompt?: string;
}

export class AiFilterSettingDto extends BaseChatbotSettingDto {
  botIdFallback?: string;
}
