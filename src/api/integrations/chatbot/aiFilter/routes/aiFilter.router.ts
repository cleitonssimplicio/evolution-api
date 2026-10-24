import { RouterBroker } from '@api/abstract/abstract.router';
import { IgnoreJidDto } from '@api/dto/chatbot.dto';
import { InstanceDto } from '@api/dto/instance.dto';
import { HttpStatus } from '@api/routes/index.router';
import { aiFilterController } from '@api/server.module';
import { instanceSchema } from '@validate/instance.schema';
import { RequestHandler, Router } from 'express';

import { AiFilterDto, AiFilterSettingDto } from '../dto/aiFilter.dto';
import {
  aiFilterIgnoreJidSchema,
  aiFilterSchema,
  aiFilterSettingSchema,
  aiFilterStatusSchema,
} from '../validate/aiFilter.schema';

export class AiFilterRouter extends RouterBroker {
  constructor(...guards: RequestHandler[]) {
    super();
    this.router
      .post(this.routerPath('create'), ...guards, async (req, res) => {
        const response = await this.dataValidate<AiFilterDto>({
          request: req,
          schema: aiFilterSchema,
          ClassRef: AiFilterDto,
          execute: (instance, data) => aiFilterController.createBot(instance, data),
        });

        res.status(HttpStatus.CREATED).json(response);
      })
      .get(this.routerPath('find'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: instanceSchema,
          ClassRef: InstanceDto,
          execute: (instance) => aiFilterController.findBot(instance),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .get(this.routerPath('fetch/:aiFilterBotId'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: instanceSchema,
          ClassRef: InstanceDto,
          execute: (instance) => aiFilterController.fetchBot(instance, req.params.aiFilterBotId),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .put(this.routerPath('update/:aiFilterBotId'), ...guards, async (req, res) => {
        const response = await this.dataValidate<AiFilterDto>({
          request: req,
          schema: aiFilterSchema,
          ClassRef: AiFilterDto,
          execute: (instance, data) => aiFilterController.updateBot(instance, req.params.aiFilterBotId, data),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .delete(this.routerPath('delete/:aiFilterBotId'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: instanceSchema,
          ClassRef: InstanceDto,
          execute: (instance) => aiFilterController.deleteBot(instance, req.params.aiFilterBotId),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .post(this.routerPath('settings'), ...guards, async (req, res) => {
        const response = await this.dataValidate<AiFilterSettingDto>({
          request: req,
          schema: aiFilterSettingSchema,
          ClassRef: AiFilterSettingDto,
          execute: (instance, data) => aiFilterController.settings(instance, data),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .get(this.routerPath('fetchSettings'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: instanceSchema,
          ClassRef: InstanceDto,
          execute: (instance) => aiFilterController.fetchSettings(instance),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .post(this.routerPath('changeStatus'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: aiFilterStatusSchema,
          ClassRef: InstanceDto,
          execute: (instance, data) => aiFilterController.changeStatus(instance, data),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .get(this.routerPath('fetchSessions/:aiFilterBotId'), ...guards, async (req, res) => {
        const response = await this.dataValidate<InstanceDto>({
          request: req,
          schema: instanceSchema,
          ClassRef: InstanceDto,
          execute: (instance) => aiFilterController.fetchSessions(instance, req.params.aiFilterBotId),
        });

        res.status(HttpStatus.OK).json(response);
      })
      .post(this.routerPath('ignoreJid'), ...guards, async (req, res) => {
        const response = await this.dataValidate<IgnoreJidDto>({
          request: req,
          schema: aiFilterIgnoreJidSchema,
          ClassRef: IgnoreJidDto,
          execute: (instance, data) => aiFilterController.ignoreJid(instance, data),
        });

        res.status(HttpStatus.OK).json(response);
      });
  }

  public readonly router: Router = Router();
}
