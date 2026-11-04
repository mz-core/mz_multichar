const elements = {
  app: document.querySelector('#app'),
  brandName: document.querySelector('#brand-name'),
  list: document.querySelector('#characters'),
  rosterStatus: document.querySelector('#roster-status'),
  empty: document.querySelector('#empty'),
  create: document.querySelector('#create'),
  details: document.querySelector('#details'),
  selectedName: document.querySelector('#selected-name'),
  selectedId: document.querySelector('#selected-id'),
  selectedBirthdate: document.querySelector('#selected-birthdate'),
  selectedGender: document.querySelector('#selected-gender'),
  selectedNationality: document.querySelector('#selected-nationality'),
  selectedPhone: document.querySelector('#selected-phone'),
  enter: document.querySelector('#enter'),
  errorBox: document.querySelector('#error-box'),
  error: document.querySelector('#error'),
  retry: document.querySelector('#retry'),
  cinematicStatus: document.querySelector('#cinematic-status')
};

let state = null;
let selectedCharacterId = null;
let busy = false;
let debugEnabled = false;
let requestTimeoutMs = 10000;
let openSequence = 0;
let renderedSequence = 0;

const debugLog = message => {
  if (debugEnabled) console.log(`[MZ_MULTICHAR][NUI] ${message}`);
};

const requestId = prefix => `${prefix}:${Date.now()}:${Math.random().toString(36).slice(2, 12)}`;

const post = async (name, data = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
      signal: controller.signal
    });
    if (!response.ok) throw new Error(`NUI request ${name} failed (${response.status})`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
};

const safeText = value => String(value ?? '').trim();
const defaultBrandName = safeText(elements.brandName.textContent) || 'MZ_CORE';

function characters() {
  return state && Array.isArray(state.characters) ? state.characters : [];
}

function selectedCharacter() {
  return characters().find(character => Number(character.characterId) === Number(selectedCharacterId));
}

function fullName(character) {
  const info = character?.charinfo || {};
  return `${safeText(info.firstname)} ${safeText(info.lastname)}`.trim() || 'Personagem sem nome';
}

function displayValue(value) {
  return safeText(value) || '—';
}

function displayGender(value) {
  const normalized = safeText(value).toLowerCase();
  if (['m', 'male', 'masculino', '0'].includes(normalized)) return 'Masculino';
  if (['f', 'female', 'feminino', '1'].includes(normalized)) return 'Feminino';
  return displayValue(value);
}

function showError(message) {
  elements.error.textContent = message || 'Falha ao carregar personagens.';
  elements.errorBox.classList.remove('hidden');
}

function clearError() {
  elements.error.textContent = '';
  elements.errorBox.classList.add('hidden');
}

function acknowledgeRendered(characterCount, invalidState) {
  const sequence = openSequence;
  if (renderedSequence === sequence) return;
  renderedSequence = sequence;
  debugLog('rendered');
  void post('rendered', { count: characterCount, invalidState: invalidState === true }).catch(renderError => {
    console.error('[MZ_MULTICHAR][NUI] rendered callback failed', renderError);
  });
}

function renderDetails() {
  const character = selectedCharacter();
  elements.details.classList.toggle('hidden', !character);
  elements.cinematicStatus.textContent = character ? 'FOCO NO PERSONAGEM' : 'CÂMERA CINEMATOGRÁFICA';
  if (!character) return;

  const info = character.charinfo || {};
  elements.selectedName.textContent = fullName(character);
  elements.selectedId.textContent = `PERSONAGEM #${displayValue(character.characterId)}`;
  elements.selectedBirthdate.textContent = displayValue(info.birthdate);
  elements.selectedGender.textContent = displayGender(info.gender);
  elements.selectedNationality.textContent = displayValue(info.nationality);
  elements.selectedPhone.textContent = displayValue(info.phone);
  elements.enter.disabled = busy;
}

async function toggleCharacterFocus(characterId) {
  if (busy) return;
  const previous = selectedCharacterId;
  selectedCharacterId = Number(previous) === Number(characterId) ? null : Number(characterId);
  clearError();
  render();
  try {
    const result = await post('focus', selectedCharacterId ? { characterId: selectedCharacterId } : {});
    if (!result?.ok) {
      selectedCharacterId = previous;
      render();
      showError(result?.error || 'Não foi possível focar o personagem.');
    }
  } catch (focusError) {
    selectedCharacterId = previous;
    render();
    showError('Falha de comunicação ao ajustar a câmera.');
    console.error('[MZ_MULTICHAR][NUI] focus failed', focusError);
  }
}

function render() {
  const validState = state && typeof state === 'object';
  const roster = validState ? characters() : [];
  const usedSlots = validState && Number.isFinite(Number(state.usedSlots)) ? Number(state.usedSlots) : roster.length;
  const maximumSlots = validState && Number.isFinite(Number(state.slots)) ? Number(state.slots) : Math.max(1, usedSlots);

  elements.brandName.textContent = safeText(state?.presentation?.brandName) || defaultBrandName;
  elements.rosterStatus.textContent = `${usedSlots} de ${maximumSlots} slots utilizados`;
  elements.create.disabled = busy || usedSlots >= maximumSlots;
  elements.list.replaceChildren();
  elements.empty.classList.toggle('hidden', roster.length !== 0);

  if (!validState) {
    elements.app.classList.remove('hidden');
    showError('Estado de personagens inválido. Consulte o F8.');
    acknowledgeRendered(0, true);
    return;
  }

  for (const character of roster) {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'character-card';
    if (Number(character.characterId) === Number(selectedCharacterId)) card.classList.add('selected');
    card.disabled = busy;

    const copy = document.createElement('span');
    copy.className = 'character-copy';
    const name = document.createElement('strong');
    name.textContent = fullName(character);
    const subtitle = document.createElement('small');
    subtitle.textContent = displayValue(character.charinfo?.nationality) === '—'
      ? 'Personagem disponível'
      : displayValue(character.charinfo?.nationality);
    copy.append(name, subtitle);

    const number = document.createElement('span');
    number.className = 'character-number';
    number.textContent = `#${displayValue(character.characterId)}`;
    card.append(copy, number);
    card.addEventListener('click', () => void toggleCharacterFocus(character.characterId));
    elements.list.append(card);
  }

  renderDetails();
  acknowledgeRendered(roster.length, false);
}

elements.enter.addEventListener('click', async () => {
  const character = selectedCharacter();
  if (!character || busy) return;
  busy = true;
  clearError();
  render();
  try {
    const result = await post('select', {
      characterId: character.characterId,
      requestId: requestId('select')
    });
    if (!result?.ok) {
      busy = false;
      render();
      showError(result?.error || 'Falha ao ativar personagem.');
    }
  } catch (requestError) {
    busy = false;
    render();
    showError('Falha de comunicação ao ativar personagem.');
    console.error('[MZ_MULTICHAR][NUI] select failed', requestError);
  }
});

elements.create.addEventListener('click', async () => {
  if (busy || elements.create.disabled) return;
  busy = true;
  clearError();
  render();
  try {
    const result = await post('create', { requestId: requestId('create') });
    if (!result?.ok) {
      busy = false;
      render();
      showError(result?.error || 'Falha ao criar personagem.');
    }
  } catch (requestError) {
    busy = false;
    render();
    showError('Falha de comunicação ao criar personagem.');
    console.error('[MZ_MULTICHAR][NUI] create failed', requestError);
  }
});

elements.retry.addEventListener('click', async () => {
  if (busy) return;
  busy = true;
  clearError();
  try {
    const result = await post('refresh');
    if (!result?.ok || !result.data || result.data.active === true || result.data.creating === true) {
      throw new Error(result?.error || 'selection_unavailable');
    }
    state = result.data;
    selectedCharacterId = null;
    busy = false;
    render();
  } catch (refreshError) {
    busy = false;
    showError('A seleção ainda não está disponível. Tente novamente em instantes.');
    console.error('[MZ_MULTICHAR][NUI] refresh failed', refreshError);
  }
});

window.addEventListener('message', event => {
  if (event.data?.action === 'open') {
    debugEnabled = event.data.debug === true;
    requestTimeoutMs = Number(event.data.requestTimeoutMs) || requestTimeoutMs;
    state = event.data.state;
    selectedCharacterId = null;
    busy = false;
    clearError();
    openSequence += 1;
    elements.app.classList.remove('hidden');
    const count = Array.isArray(state?.characters) ? state.characters.length : 0;
    debugLog(`roster received count=${count}`);
    render();
  } else if (event.data?.action === 'error') {
    elements.app.classList.remove('hidden');
    showError(event.data.message || 'Falha ao carregar personagens.');
  } else if (event.data?.action === 'close') {
    elements.app.classList.add('hidden');
    state = null;
    selectedCharacterId = null;
    busy = false;
    clearError();
  }
});

window.addEventListener('error', event => {
  console.error('[MZ_MULTICHAR][NUI] JavaScript error', event.error || event.message);
});

window.addEventListener('unhandledrejection', event => {
  console.error('[MZ_MULTICHAR][NUI] unhandled promise rejection', event.reason);
});

const announceReady = async (attempt = 1) => {
  try {
    const result = await post('ready');
    if (result?.ok === true) {
      debugEnabled = result.debug === true;
      requestTimeoutMs = Number(result.requestTimeoutMs) || requestTimeoutMs;
      debugLog('DOM ready');
      return;
    }
  } catch (readyError) {
    if (attempt >= 20) console.error('[MZ_MULTICHAR][NUI] ready failed', readyError);
  }
  if (attempt < 20) setTimeout(() => announceReady(attempt + 1), 500);
};

announceReady();
