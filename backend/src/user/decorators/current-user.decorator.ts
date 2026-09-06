import { ExecutionContext, createParamDecorator } from '@nestjs/common';

/**
 * Extracts the JWT payload attached to `req.user` by JwtAccessGuard.
 *
 * Usage:
 *   @UseGuards(JwtAccessGuard)
 *   @Get('me')
 *   me(@CurrentUser() user: { sub: string; type: 'access' | 'refresh' }) {
 *     // user.sub is the authenticated user's id
 *   }
 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext) => {
    const req = ctx.switchToHttp().getRequest<{ user?: { sub: string; type: string } }>();
    return req.user;
  },
);
