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
  systemPrompt?: string;
  filterCategories?: AiFilterCategory[];
  autoRespondPrompt?: string;
}

export class AiFilterSettingDto extends BaseChatbotSettingDto {
  botIdFallback?: string;
}
