Config = Config or {}

-- Ative temporariamente na VPS para registrar o lifecycle visual da selecao.
Config.Debug = true

-- Usa automaticamente `sets sv_projectName` do server.cfg.
-- Se estiver vazio ou desativado, exibe o nome padrao abaixo.
Config.Brand = {
  useServerProjectName = true,
  name = 'MZ_CORE'
}

Config.Selection = {
  nuiReadyTimeoutMs = 8000,
  nuiRenderTimeoutMs = 8000,
  transitionTimeoutMs = 15000,
  spawnTimeoutMs = 20000,
  rosterRetryMs = 1500,
  rosterMaxAttempts = 5,
  nuiRequestTimeoutMs = 10000,
  fadeOutMs = 250,
  fadeInMs = 500,
  collisionTimeoutMs = 3000
}

-- Cena exclusivamente visual. Os peds abaixo nunca representam players ativos.
Config.SelectionScene = {
  location = { x = -777.54, y = 331.47, z = 211.40, heading = 180.0 },
  loadTimeoutMs = 5000,
  modelTimeoutMs = 5000,
  animationTimeoutMs = 2500,
  maxPreviewPeds = 5,
  cameraTickMs = 16,
  cameraBlendMs = 650,
  cameraFov = 46.0,
  focusFov = 38.0,
  focusTransitionMs = 700,

  slots = {
    {
      coords = { x = -792.79, y = 332.97, z = 206.62 },
      zByGender = { male = 206.62, female = 206.52 },
      zOffset = -1.0,
      heading = 187.09,
      animation = {
        dict = 'anim_casino_a@amb@casino@games@insidetrack@ped_male@regular@02b@base',
        name = 'base'
      },
      focusCamera = {
        coords = { x = -792.09, y = 331.96, z = 206.95 },
        lookAt = { x = -792.79, y = 332.97, z = 206.80 },
        fov = 38.0
      }
    },
    {
      coords = { x = -802.27, y = 338.63, z = 206.21 },
      zOffset = -1.0,
      heading = 85.04,
      animation = { dict = 'amb@world_human_yoga@male@base', name = 'base_a' },
      focusCamera = {
        coords = { x = -803.51, y = 337.79, z = 206.75 },
        lookAt = { x = -802.27, y = 338.63, z = 206.55 },
        fov = 38.0
      }
    },
    {
      coords = { x = -793.43, y = 341.39, z = 206.21 },
      zOffset = -1.0,
      heading = 238.12,
      animation = { dict = 'timetable@ron@ig_5_p3', name = 'ig_5_p3_base' },
      focusCamera = {
        coords = { x = -793.23, y = 340.30, z = 206.80 },
        lookAt = { x = -793.43, y = 341.39, z = 206.55 },
        fov = 38.0
      }
    },
    {
      coords = { x = -795.90, y = 338.40, z = 202.15 },
      zOffset = -1.0,
      heading = 87.88,
      animation = { dict = 'amb@world_human_sunbathe@male@back@idle_a', name = 'idle_a' },
      focusCamera = {
        coords = { x = -796.31, y = 338.40, z = 202.85 },
        lookAt = { x = -795.90, y = 338.40, z = 202.15 },
        fov = 40.0
      }
    },
    {
      coords = { x = -789.30, y = 330.43, z = 206.21 },
      zOffset = -1.0,
      heading = 0.0,
      animation = { dict = 'amb@prop_human_bbq@male@idle_b', name = 'idle_e' },
      focusCamera = {
        coords = { x = -789.80, y = 331.33, z = 206.90 },
        lookAt = { x = -789.30, y = 330.43, z = 206.70 },
        fov = 38.0
      }
    }
  },

  cinematicPaths = {
    {
      from = { x = -797.09, y = 335.62, z = 201.41 },
      to = { x = -786.35, y = 336.11, z = 201.41 },
      lookFrom = { x = -796.04, y = 342.89, z = 201.41 },
      lookTo = { x = -787.09, y = 341.61, z = 201.41 },
      duration = 12000
    },
    {
      from = { x = -779.52, y = 341.71, z = 207.62 },
      to = { x = -800.83, y = 334.50, z = 206.21 },
      lookFrom = { x = -787.66, y = 338.35, z = 206.21 },
      lookTo = { x = -797.68, y = 328.24, z = 206.21 },
      duration = 20000
    },
    {
      from = { x = -798.00, y = 326.99, z = 207.51 },
      to = { x = -790.06, y = 334.79, z = 206.21 },
      lookFrom = { x = -781.95, y = 336.55, z = 207.62 },
      lookTo = { x = -795.00, y = 343.17, z = 206.21 },
      duration = 13000
    }
  }
}
