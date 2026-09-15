# Changelog

## [0.1.1](https://github.com/JaJoJi/mobile-final-project/compare/mobile-final-project-v0.1.0...mobile-final-project-v0.1.1) (2026-09-15)


### Features

* **battle:** combat animations, server snapshots, and reconnect ([5bba16d](https://github.com/JaJoJi/mobile-final-project/commit/5bba16dae61237d72d1aa4c8cc50e61a6d04b7a3))
* **be:** P0-BE-01 Redis Lua script loader ([75282f2](https://github.com/JaJoJi/mobile-final-project/commit/75282f27ba70ee72817f7be1fcb6d8702686f3d7))
* **be:** P0-BE-02 TypeORM entity registration + migration runner ([4dd0f6f](https://github.com/JaJoJi/mobile-final-project/commit/4dd0f6fcce482dc54d6f8e5e9dde3b67265776cf))
* **be:** P0-BE-03 BullMQ queue + worker processor module ([48f3cef](https://github.com/JaJoJi/mobile-final-project/commit/48f3cef19adcd132547b8dbece8d9f01ec9e7b30))
* **be:** P0-BE-04 WebSocket gateway module (Nest + socket.io) ([48c80c0](https://github.com/JaJoJi/mobile-final-project/commit/48c80c05e086da8af268ce49026181d402386cae)), closes [#145](https://github.com/JaJoJi/mobile-final-project/issues/145)
* **be:** P0-BE-05 Pub/Sub cross-instance bridge ([c774058](https://github.com/JaJoJi/mobile-final-project/commit/c774058b04eaf24fef0a0f8f4859e8ab6caf5e37)), closes [#146](https://github.com/JaJoJi/mobile-final-project/issues/146)
* **be:** P0-BE-06 Lua scripts (atomic primitives) ([29ecfd8](https://github.com/JaJoJi/mobile-final-project/commit/29ecfd8badeb3b81a33fbcf11e81e5b68507fe67)), closes [#147](https://github.com/JaJoJi/mobile-final-project/issues/147)
* **be:** P0-BE-07 Match + MatchRound entities + CreateMatches migration ([86e3439](https://github.com/JaJoJi/mobile-final-project/commit/86e3439a957a949213a38205724696f9e29f4d6f)), closes [#148](https://github.com/JaJoJi/mobile-final-project/issues/148)
* **be:** P0-BE-08 WS payload DTOs + validation pipe ([9320d22](https://github.com/JaJoJi/mobile-final-project/commit/9320d2259956b1eabef7ab7880dacf904c6209cf)), closes [#149](https://github.com/JaJoJi/mobile-final-project/issues/149)
* **be:** P0-BE-09 combat engine (Cycle Processor) ([fd59a15](https://github.com/JaJoJi/mobile-final-project/commit/fd59a15ff04db4e5cba84ea691a383f753c05358)), closes [#150](https://github.com/JaJoJi/mobile-final-project/issues/150)
* **be:** P0-BE-10 WS event handlers ([21eb205](https://github.com/JaJoJi/mobile-final-project/commit/21eb205d6f01b62318d804a4b8d77257b3e02b5f))
* **be:** P0-BE-10 WS event handlers ([731d2b5](https://github.com/JaJoJi/mobile-final-project/commit/731d2b53babc1f7325d56f301d4c22a50a43b846))
* **be:** P0-BE-11 matchmaking logic ([127f271](https://github.com/JaJoJi/mobile-final-project/commit/127f27189da99e53fb6ac10a6860d770320c0c4c))
* **be:** P0-BE-11 matchmaking logic ([07e31c7](https://github.com/JaJoJi/mobile-final-project/commit/07e31c7994f2db9af191f8a502a4562a9bec9f30))
* **be:** P0-BE-12 Match Lifecycle service ([5f29cb7](https://github.com/JaJoJi/mobile-final-project/commit/5f29cb74467e51095793bbc2e69471fff2f80775))
* **be:** P0-BE-12 Match Lifecycle service ([f6e0dc0](https://github.com/JaJoJi/mobile-final-project/commit/f6e0dc037bac572c71eb4c979f2969dcd14bd8ca))
* **be:** P0-BE-13 round orchestrator ([16285db](https://github.com/JaJoJi/mobile-final-project/commit/16285db55e79f944ce0b63f4776a938918f4295f))
* **be:** P0-BE-13 round orchestrator ([50d89fd](https://github.com/JaJoJi/mobile-final-project/commit/50d89fdcba9588b9a0c5f9a7f26fb9575e4ef593))
* **be:** P0-BE-14 shop system ([d31518f](https://github.com/JaJoJi/mobile-final-project/commit/d31518faa569faf8bd43b85c1256d5f34ba6d8e5))
* **be:** P0-BE-14 shop system ([af4d4c9](https://github.com/JaJoJi/mobile-final-project/commit/af4d4c9e8981bbf7ae9cdc6ffc609cf3c692895a))
* **be:** P1-BE-01 pino structured logs + WS rate limit + REST error envelope ([2fe9736](https://github.com/JaJoJi/mobile-final-project/commit/2fe97369c89702470894725de42c3845acecc2f4))
* **be:** P1-BE-01 pino structured logs + WS rate limit + REST error envelope ([6202260](https://github.com/JaJoJi/mobile-final-project/commit/6202260b5772297dec1e738de5daf05e774e9e98)), closes [#113](https://github.com/JaJoJi/mobile-final-project/issues/113)
* **be:** P3-BE-03 (part 1) helmet, graceful shutdown, health split, swagger ([2a35a52](https://github.com/JaJoJi/mobile-final-project/commit/2a35a52af45875529f48a43858a4b6c472a20e58)), closes [#133](https://github.com/JaJoJi/mobile-final-project/issues/133)
* **devops:** P3-DO-02 auto-publish backend image to GHCR ([2b7eca8](https://github.com/JaJoJi/mobile-final-project/commit/2b7eca8f5672b7325151030252746dddd557770a)), closes [#137](https://github.com/JaJoJi/mobile-final-project/issues/137)
* **devops:** P3-DO-11 release automation via release-please ([44c776a](https://github.com/JaJoJi/mobile-final-project/commit/44c776ad671217981c85a57bd517fc6349431108))
* **devops:** P3-DO-11 release automation via release-please ([0397df9](https://github.com/JaJoJi/mobile-final-project/commit/0397df95cfa7766e076459cdfc341f06664d2b1a)), closes [#195](https://github.com/JaJoJi/mobile-final-project/issues/195)
* **devops:** P3-DO-13 parked Jenkins pipeline ([41e379e](https://github.com/JaJoJi/mobile-final-project/commit/41e379ecdfb3562087bb187dc529a67ba429ed6b))
* **devops:** P3-DO-13 parked Jenkins pipeline ([a3942ac](https://github.com/JaJoJi/mobile-final-project/commit/a3942ac210486993c99fe28d68a4d1991dcd9493)), closes [#190](https://github.com/JaJoJi/mobile-final-project/issues/190)
* **fe:** complete P0-FE-04 in-game experience ([4d873a3](https://github.com/JaJoJi/mobile-final-project/commit/4d873a3425d3344ff360606ad10012f4fcbf2810))
* **fe:** complete P0-FE-04 in-game experience ([f1ee229](https://github.com/JaJoJi/mobile-final-project/commit/f1ee2292433831e4fc360f7079cd51a253ba8061))
* **fe:** P0-FE-01 WebSocket client + typed game event models ([6798802](https://github.com/JaJoJi/mobile-final-project/commit/6798802964cff264e1c7f7fb1751b18c2a0ddc61))
* **fe:** P0-FE-01 WebSocket client + typed game event models ([b2a4bc9](https://github.com/JaJoJi/mobile-final-project/commit/b2a4bc970a9fb88655aa00565cd7f4d64598fc97)), closes [#107](https://github.com/JaJoJi/mobile-final-project/issues/107)
* **fe:** P0-FE-02 auto-refresh tokens, session restore, go_router ([8f831a8](https://github.com/JaJoJi/mobile-final-project/commit/8f831a841e348d40b784c19eaaa09e4bc6b06ec3)), closes [#108](https://github.com/JaJoJi/mobile-final-project/issues/108)
* **fe:** P0-FE-03 lobby + WS lifecycle fix + 2-client E2E proof ([544c7a3](https://github.com/JaJoJi/mobile-final-project/commit/544c7a3a16ff1accf928e9f068ac83826de8ab9b)), closes [#109](https://github.com/JaJoJi/mobile-final-project/issues/109)
* **fe:** P0-FE-06 design tokens + shared widget library ([f87310d](https://github.com/JaJoJi/mobile-final-project/commit/f87310d02610b8962eb4fa0565e25e61a0970a69)), closes [#112](https://github.com/JaJoJi/mobile-final-project/issues/112)
* **fe:** P0-FE-06b wire chess-asset art into UnitAvatar ([b318a8e](https://github.com/JaJoJi/mobile-final-project/commit/b318a8e0f6c163906f15ccde7501c5ac954915c5)), closes [#171](https://github.com/JaJoJi/mobile-final-project/issues/171)
* **fe:** P1-FE-01 past-matches list + detail screens ([33b9a24](https://github.com/JaJoJi/mobile-final-project/commit/33b9a247f7cebf2ed095cfebd512e8e8ffbff931)), closes [#115](https://github.com/JaJoJi/mobile-final-project/issues/115)
* **fe:** P1-FE-02 my-account screen — theme + reconnect settings ([6e27aef](https://github.com/JaJoJi/mobile-final-project/commit/6e27aefd3f5a881b9a42b7a17f2c00e3bb743f8e)), closes [#116](https://github.com/JaJoJi/mobile-final-project/issues/116)
* **fe:** P4-FE-01 attacker recoil so melee units visibly move ([0cedf25](https://github.com/JaJoJi/mobile-final-project/commit/0cedf25dfec422a93c44200d489da644f9eedcf7)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 CombatEffectsOverlay renders lunge/projectile at real tile positions ([01c6005](https://github.com/JaJoJi/mobile-final-project/commit/01c60050077f51e41904af22fa0b1ae7a2d2cdbf))
* **fe:** P4-FE-01 melee attacker sprite travels to its target ([1616147](https://github.com/JaJoJi/mobile-final-project/commit/16161473b517cc54385bad8e4c18a86f04c3c3ce)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 mount CombatEffectsOverlay above the battle boards ([63512d1](https://github.com/JaJoJi/mobile-final-project/commit/63512d1cbb06469b8a074a8752c00fa4213172bd))
* **fe:** P4-FE-01 pure combat-effects math (event window + tile geometry) ([5491a6f](https://github.com/JaJoJi/mobile-final-project/commit/5491a6fe7d304e398fa2f9c27902ce7b55fe3962))
* **fe:** P4-FE-02 ranged projectile travels to target and hits before disappearing ([1c9cae9](https://github.com/JaJoJi/mobile-final-project/commit/1c9cae945e6974b1ff934564b4020bd0246918c1))
* **fe:** stack landscape's shop vertically and give it back width for the board ([c4dbdfa](https://github.com/JaJoJi/mobile-final-project/commit/c4dbdfa76ef41bd2ef2f635706d3944d05fa906a))
* **match:** overhaul game presentation and manual unit fusion ([2f74f01](https://github.com/JaJoJi/mobile-final-project/commit/2f74f0113976525c204951a2381c32c35e44e655))


### Bug Fixes

* **be:** align match lifecycle with P0-FE-04 client ([10521c6](https://github.com/JaJoJi/mobile-final-project/commit/10521c6cf9a8d71d903185f0d6acd06c0d98808a))
* **be:** P1-BE-01 production safety gaps ([89eb26b](https://github.com/JaJoJi/mobile-final-project/commit/89eb26bc619fe6d265600accde7430b1b8e34d65))
* **be:** P1-BE-01 production safety gaps ([5aa86e1](https://github.com/JaJoJi/mobile-final-project/commit/5aa86e127a6e6c4870244833cc8e3c2fd9fb8487))
* **ci:** regenerate golden fixture, fix lua test timing, format dart files ([2533336](https://github.com/JaJoJi/mobile-final-project/commit/25333361c65b19b57b8f7347f0336a8ab1c85811))
* **devops:** P3-DO-22 pin LF for shell/sql scripts, fix replica init ([419a786](https://github.com/JaJoJi/mobile-final-project/commit/419a786d38407578fbce5e57260a6146d8dc089a))
* **devops:** P3-DO-22 pin LF for shell/sql scripts, fix replica init ([a02036e](https://github.com/JaJoJi/mobile-final-project/commit/a02036e98079685fb0c427b13e99f3a205e35a11)), closes [#226](https://github.com/JaJoJi/mobile-final-project/issues/226)
* **fe:** drop DeathEvent from the playhead — kills looked like corpses fighting back ([781aa77](https://github.com/JaJoJi/mobile-final-project/commit/781aa772a8b39b3108a3a95dc0112a8550123f1c))
* **fe:** exempt tile hit-effect controllers from reduced-motion scaling ([9bcabd6](https://github.com/JaJoJi/mobile-final-project/commit/9bcabd66370466a245eebc3c58f867ac5dc0233e))
* **fe:** face front rows toward each other in landscape combat ([c28339d](https://github.com/JaJoJi/mobile-final-project/commit/c28339da0dc0c91ab1e121aecad79b5b20fd8959))
* **fe:** give board unit art real headroom instead of jamming it to the top ([7939da5](https://github.com/JaJoJi/mobile-final-project/commit/7939da535dc452ee6019595e0c54657dbfae89e6))
* **fe:** keep the landscape shop card change out of portrait ([0bcb01a](https://github.com/JaJoJi/mobile-final-project/commit/0bcb01af04611ab3866a0629dffc2d36eb39042a))
* **fe:** landscape shop card + shrink the panel to match ([6018b41](https://github.com/JaJoJi/mobile-final-project/commit/6018b41d2370b4ec026f50e74a978d214c75de52))
* **fe:** left-align the sold placeholder text in the landscape card ([4b7e3df](https://github.com/JaJoJi/mobile-final-project/commit/4b7e3df6e8e22798d04f1fd12d5fbbb8eaed301f))
* **fe:** left-align the sold placeholder text in the landscape card ([aa16e93](https://github.com/JaJoJi/mobile-final-project/commit/aa16e932a7b9f8e06e6cf5e636feb12aa2121000))
* **fe:** P4-FE-01 anchor combat playback to wall time, ack on a timer ([846900f](https://github.com/JaJoJi/mobile-final-project/commit/846900f8daf300514ec9bd2a589dddc355952597)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 anchor playback to frame time, not DateTime.now() ([276b7f7](https://github.com/JaJoJi/mobile-final-project/commit/276b7f7dd4006164c76fae1e172dcc1cc7773e08)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 anchor replay to the server's endedAt, not local arrival ([a26db37](https://github.com/JaJoJi/mobile-final-project/commit/a26db37da6632081868e5b76036d407ce11d3fec)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 exempt the combat playhead from reduced-motion scaling ([8b42b58](https://github.com/JaJoJi/mobile-final-project/commit/8b42b58af99d4a00b359118e6e7ce496cae7ab89))
* **fe:** P4-FE-01 make attacker recoil viewer-relative, not side-absolute ([adf8529](https://github.com/JaJoJi/mobile-final-project/commit/adf8529f1e5aaf9b08cbfd6e544371b35f0bfe1d)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 replay missed combat batch on BattleView mount ([66fd069](https://github.com/JaJoJi/mobile-final-project/commit/66fd0697c6a903fdb29362f30aa8f99f781527c8)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 size combat effects from the tile, not fixed pixels ([cd4ed08](https://github.com/JaJoJi/mobile-final-project/commit/cd4ed08764241b8c30c3015d5eaec87ae9a8b4a3)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 stop fireImmediately aborting playback before it starts ([da1a45a](https://github.com/JaJoJi/mobile-final-project/commit/da1a45aa849bfda97c475b79c684b5ab96200860)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 stop rounds resolving before the replay plays ([95c32a8](https://github.com/JaJoJi/mobile-final-project/commit/95c32a80285437fde7f0900dcf622d340a3fbda4))
* **fe:** placeholder_screens_test — drop history cases ([dad2073](https://github.com/JaJoJi/mobile-final-project/commit/dad207311e0fcdfa46b931795a6aadd04833f8de))
* **fe:** post-merge combat pacing, board head-clip, shop card blowup ([6e38b62](https://github.com/JaJoJi/mobile-final-project/commit/6e38b62a4e3081ccbb2eff199d105c365d89cd2a))
* **fe:** shrink shop card by merging name/price onto one row ([cb3656e](https://github.com/JaJoJi/mobile-final-project/commit/cb3656e12ab90ca49702e3710948450b2f89cc41))
* **fe:** stop shop cards stretching to the panel's height on wide viewports ([da1672b](https://github.com/JaJoJi/mobile-final-project/commit/da1672ba454ff137638a5738f64681628f5d3626))
* **fe:** unbreak dev — placeholder_screens_test history cases ([2bdc977](https://github.com/JaJoJi/mobile-final-project/commit/2bdc9777d4ce0d76f0b0635b4046fd4e78198913))
* **mobile:** add null assertion for _controller.events ([cf7237d](https://github.com/JaJoJi/mobile-final-project/commit/cf7237d324dbf7f71d55faf9096e1efc275d8a6c))
* **mobile:** resolve flutter analyze warnings in battle_view.dart ([40f5eac](https://github.com/JaJoJi/mobile-final-project/commit/40f5eac6d3e0da564cb80ce36691757c177f3431))


### Performance

* **fe:** P4-FE-01 memoise deriveUnitStates against the event index ([3d1513a](https://github.com/JaJoJi/mobile-final-project/commit/3d1513a79764452e46be5c8d8dbe3753b5922982)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)


### Chores

* **be:** Dockerfile npm ci + devDep-free runtime; fix worker comment ([c58e749](https://github.com/JaJoJi/mobile-final-project/commit/c58e749ccace515d47bb77f4451ca82b9382aa91)), closes [#174](https://github.com/JaJoJi/mobile-final-project/issues/174)
* **be:** Dockerfile npm ci + slim runtime; worker comment fix ([18644f0](https://github.com/JaJoJi/mobile-final-project/commit/18644f0aa33d1c8dc00f4fadb25d769f02e66b0b))
* **deps-dev:** bump @types/node from 22.20.1 to 26.5.1 in /backend ([494fd30](https://github.com/JaJoJi/mobile-final-project/commit/494fd30eda053ed8a4437e579251edccf6ef9526))
* **deps-dev:** bump @types/node from 22.20.1 to 26.5.1 in /backend ([26f8579](https://github.com/JaJoJi/mobile-final-project/commit/26f85790683ccecb24d238895eccf5192e859641))
* **deps:** bump actions/setup-node from 4 to 7 ([56798a4](https://github.com/JaJoJi/mobile-final-project/commit/56798a46ac15d741ab9aaff3870383671d0d4beb))
* **deps:** bump actions/setup-node from 4 to 7 ([b63d31f](https://github.com/JaJoJi/mobile-final-project/commit/b63d31f251ff950f1bf9de771a4360062650fa17))
* **deps:** bump docker/build-push-action from 5 to 7 ([23bc377](https://github.com/JaJoJi/mobile-final-project/commit/23bc37771d43ecfda64f665766d0e16787631f94))
* **deps:** bump docker/build-push-action from 5 to 7 ([cd6691e](https://github.com/JaJoJi/mobile-final-project/commit/cd6691e2f68f984922400ca314e3e449cf08d20d))
* **deps:** bump flutter_lints from 4.0.0 to 6.0.0 in /mobile ([51c28f0](https://github.com/JaJoJi/mobile-final-project/commit/51c28f0001d807ade79a49f26131f451609ab972))
* **deps:** bump flutter_lints from 4.0.0 to 6.0.0 in /mobile ([ea3039c](https://github.com/JaJoJi/mobile-final-project/commit/ea3039c9e97d504ec40bd736a3505d85f388d4aa))
* **fe:** add Flutter Web platform scaffold ([be5f5ef](https://github.com/JaJoJi/mobile-final-project/commit/be5f5ef4fe15099bbeec3eb47eaf1b481e58cd87))
* **fe:** P3-FE-02 lint, error logger, accessibility pass ([6e93e52](https://github.com/JaJoJi/mobile-final-project/commit/6e93e52fa5cf4009c64dd15ba38ce8949d15ae77)), closes [#135](https://github.com/JaJoJi/mobile-final-project/issues/135)
* **fe:** P4-FE-01 temporary on-screen combat diagnostic ([13a819e](https://github.com/JaJoJi/mobile-final-project/commit/13a819ea737b3ceba77b4727134042cb5016b95e)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* **fe:** P4-FE-01 trace the combat replay pipeline in release builds ([2ab71f0](https://github.com/JaJoJi/mobile-final-project/commit/2ab71f058504104cf800cdb8866b1ed585142793))
* fix dart format and analyze issues on dev branch ([b2af427](https://github.com/JaJoJi/mobile-final-project/commit/b2af42773a0bc9e42baca9af38db1c357adc169d))
* fix dart format on dev branch ([51406c4](https://github.com/JaJoJi/mobile-final-project/commit/51406c47af89545a21acca0cced3d57333c341d1))
* format dart files ([ea7c034](https://github.com/JaJoJi/mobile-final-project/commit/ea7c034d2542d1f679d6e90f88baf65b6270b896))
* format dart files ([2ee7f63](https://github.com/JaJoJi/mobile-final-project/commit/2ee7f63b19a0cac482bf2427a5ecfc5ab929b6a2))
* **repo:** P3-DO-06 repo hygiene sweep ([ec4238a](https://github.com/JaJoJi/mobile-final-project/commit/ec4238a3b78a58b59e052eecdb1753d0926115ed)), closes [#141](https://github.com/JaJoJi/mobile-final-project/issues/141)
* **repo:** remove dependabot config ([cff4dda](https://github.com/JaJoJi/mobile-final-project/commit/cff4ddab543a5d5a5faf82b488364079555bba57))
* **repo:** remove dependabot config ([11a52e2](https://github.com/JaJoJi/mobile-final-project/commit/11a52e26bdb9bc40d1f4adec7626c07c9791f4c6))


### Documentation

* add rendered HTML design kit alongside the spec ([cee23bc](https://github.com/JaJoJi/mobile-final-project/commit/cee23bcf9813a3353d89c96a83e39e42f63c8eab))
* add UX/UI design spec (P0-FE-00) ([9ea04dc](https://github.com/JaJoJi/mobile-final-project/commit/9ea04dce7906eb25ae2baffcd80e05785940d00e))
* **devops:** P3-DO-12 operations runbook ([468ca11](https://github.com/JaJoJi/mobile-final-project/commit/468ca1161dee572e72f96a1300338ff779d47e0a))
* **devops:** P3-DO-12 operations runbook ([d3b10ea](https://github.com/JaJoJi/mobile-final-project/commit/d3b10ea7f4575c76381cc5ec338a19a1a9921370)), closes [#196](https://github.com/JaJoJi/mobile-final-project/issues/196)
* **fe:** P4-FE-01 fix stale comment in deriveUnitStates ([080c637](https://github.com/JaJoJi/mobile-final-project/commit/080c637a14d701def85351fd3e707a2614682c22)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* P4-FE-01 combat effects overlay design ([0d715ae](https://github.com/JaJoJi/mobile-final-project/commit/0d715aed69db2d2ec9c8a2101b1928f9dbfd87be)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)
* P4-FE-01 combat effects overlay implementation plan ([9a902bf](https://github.com/JaJoJi/mobile-final-project/commit/9a902bfb81bef675bf9780cf4a2efece29b87118)), closes [#214](https://github.com/JaJoJi/mobile-final-project/issues/214)

## Changelog

Managed by [release-please](https://github.com/googleapis/release-please) from conventional commit messages on `main`. Entries below this line are generated automatically — do not hand-edit.
