import consumer from "./channels/consumer";

document.addEventListener('turbo:load', () => {
  const chatWindow = document.getElementById('chat-window');
  const messageInput = document.getElementById('message-input');
  const newMessageForm = document.getElementById('new-message-form');

  if (!chatWindow || !messageInput || !newMessageForm) return;

  const matchId = chatWindow.dataset.matchId;
  const currentUserId = parseInt(chatWindow.dataset.currentUserId, 10);

  let typingTimer;
  const TYPING_TIMEOUT = 3000;

  // =======================================================
  //   SUBSCRIPTION
  // =======================================================
  const matchChannel = consumer.subscriptions.create(
    { channel: "MatchChannel", match_id: matchId },
    {
      connected() {
        console.log("Conectado ao match", matchId);
        scrollToBottom(); // Rola para o fim ao conectar
      },

      received(data) {
        // -------------------------
        //    INDICADOR DE DIGITAÇÃO
        // -------------------------
        if (Object.prototype.hasOwnProperty.call(data, "typing")) {
          if (data.user_id == currentUserId) return;
          updateTypingIndicator(data);
          return;
        }

        // -------------------------
        //     MENSAGEM RECEBIDA
        // -------------------------
        if (data.message) {
    appendMessageToDOM(data.message);

    // --- LÓGICA DE MOVER PARA O TOPO ---
    // 1. Tenta encontrar a linha da conversa na lista lateral/index
    const conversationList = document.getElementById('conversations-master-list');
    // Você precisa adicionar id="match-row-<%= match.id %>" no seu index.html.erb
    const conversationRow = document.getElementById(`match-row-${data.message.match_id}`);

    if (conversationList && conversationRow) {
      // Move para o topo da lista
      conversationList.prepend(conversationRow);

      // Atualiza o texto da prévia da mensagem na lista
      const lastMsgText = conversationRow.querySelector('.conv-last-message');
      if (lastMsgText) {
        lastMsgText.innerText = data.message.content.substring(0, 30);
      }
      
      // Remove o prefixo "Você:" se a mensagem for de outra pessoa
      const prefix = conversationRow.querySelector('.msg-prefix');
      if (prefix && data.message.sender_id !== currentUserId) {
        prefix.remove();
      }
    }
  }
},

      sendTypingStatus(isTyping) {
        this.perform("receive", { typing: isTyping });
      }
    }
  );

  // --- LÓGICA DE LIMPAR CONVERSA (AJUSTADA) ---
const clearBtn = document.getElementById('clear-chat-btn');
if (clearBtn) {
  // O button_to cria um formulário, então pegamos o form mais próximo
  const clearForm = clearBtn.closest('form'); 
  
  clearForm.addEventListener('submit', (e) => {
    e.preventDefault(); 

    fetch(clearForm.action, {
      method: "DELETE",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "application/json"
      }
    })
    .then(response => {
      if (response.ok) {
        // 1. Remove as mensagens e os divisores de data visualmente
        const itemsToRemove = chatWindow.querySelectorAll('.message-row, .date-separator');
        itemsToRemove.forEach(m => m.remove());
        
        // 2. Fecha o menu dropdown
        const menu = document.getElementById('chat-options-menu');
        if (menu) menu.classList.add('hidden');
        
        console.log("Conversa limpa com sucesso!");
      }
    })
    .catch(err => console.error("Erro ao limpar:", err));
  });
}

// =======================================================
  //   LÓGICA DO MENU DROPDOWN (CORRIGIDA E BLINDADA)
  // =======================================================
  const menuBtn = document.getElementById('chat-options-btn');
  const menuDropdown = document.getElementById('chat-options-menu');

  if (menuBtn && menuDropdown) {
    // 1. CLONE NODE: Isso remove qualquer listener antigo que o Turbo tenha deixado
    //    Evita o bug de "abrir e fechar imediatamente"
    const newBtn = menuBtn.cloneNode(true);
    menuBtn.parentNode.replaceChild(newBtn, menuBtn);

    // 2. Adiciona o evento no NOVO botão limpo
    newBtn.addEventListener('click', (e) => {
      e.preventDefault();  // Impede submit se estiver dentro de form
      e.stopPropagation(); // Impede que o clique suba para o document
      
      menuDropdown.classList.toggle('hidden');
      console.log("Botão clicado -> Menu alternado");
    });

    // 3. Fechar ao clicar fora
    // Nota: Usamos 'newBtn' aqui porque 'menuBtn' não existe mais no DOM
    document.addEventListener('click', (e) => {
      const clickedInsideMenu = menuDropdown.contains(e.target);
      const clickedOnBtn = newBtn.contains(e.target);

      if (!clickedInsideMenu && !clickedOnBtn) {
        // Só fecha se estiver aberto
        if (!menuDropdown.classList.contains('hidden')) {
           menuDropdown.classList.add('hidden');
        }
      }
    });
  }

  // =======================================================
  //   ATUALIZA TYPING INDICATOR
  // =======================================================
  function updateTypingIndicator(data) {
    const typing = document.getElementById("typing-indicator");
    if (!typing) return; // Segurança caso o elemento não exista

    if (data.typing === true) {
      typing.innerHTML = `
        <div class="typing-user" style="color: #888; font-size: 0.8rem; margin-left: 20px;">
           ${data.user_name || "Alguém"} está digitando...
        </div>
      `;
      typing.style.display = "block";
      scrollToBottom();
    } else {
      typing.style.display = "none";
    }
  }

  // =======================================================
  //   CAPTURA DE "ESTÁ DIGITANDO"
  // =======================================================
  if (messageInput) {
    messageInput.addEventListener("input", () => {
      matchChannel.sendTypingStatus(true);
      clearTimeout(typingTimer);
      typingTimer = setTimeout(() => {
        matchChannel.sendTypingStatus(false);
      }, TYPING_TIMEOUT);
    });
  }

  // =======================================================
  //   SUBMIT DA MENSAGEM
  // =======================================================
  newMessageForm.addEventListener("submit", (e) => {
    // Nota: Se você usa data-remote="true" no Rails form, 
    // o Rails já lida com o envio via AJAX (ujs/turbo).
    // Aqui estamos apenas limpando o input visualmente para UX rápida.
    
    // Se você quiser controlar o fetch manualmente, mantenha o e.preventDefault().
    // Se quiser deixar o Rails controlar, remova o e.preventDefault() e o fetch abaixo,
    // mas garanta que o controller responda com head :ok ou JS.
    
    // Vamos manter o padrão manual para garantir compatibilidade com o código anterior:
    e.preventDefault();

    const content = messageInput.value.trim();
    if (!content) return;

    messageInput.value = "";
    messageInput.focus();
    matchChannel.sendTypingStatus(false);

    fetch(newMessageForm.action, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      },
      body: JSON.stringify({ message: { content } }),
    })
    .then(async (response) => {
      if (!response.ok) {
        console.error("Erro ao enviar mensagem");
      }
      // O ActionCable vai devolver a mensagem via broadcast, 
      // então não precisamos adicioná-la aqui manualmente para evitar duplicatas.
    })
    .catch((error) => console.error(error));
  });

 // =======================================================
  //   APPEND NO DOM (DESIGN NOVO CORRIGIDO)
  // =======================================================
  function appendMessageToDOM(message) {
    if (document.getElementById(`msg-${message.id}`)) return;

    const isSender = message.sender_id === currentUserId;
    const el = document.createElement("div");

    // 1. Mantém a estrutura de classes idêntica ao HTML.erb
    el.className = `message-row ${isSender ? "sent" : "received"}`;
    el.id = `msg-${message.id}`;

    // 2. Monta o HTML do Avatar (apenas para recebidas)
    let avatarHtml = "";
    if (!isSender) {
        const avatarSrc = message.avatar_url; 
        const displayName = message.user_name || "?";
        
        avatarHtml = `<div class="msg-avatar-container">`;
        if (avatarSrc) {
            avatarHtml += `<img class="msg-avatar" src="${avatarSrc}">`;
        } else {
            avatarHtml += `<div class="msg-avatar-placeholder">${displayName.charAt(0).toUpperCase()}</div>`;
        }
        avatarHtml += `</div>`;
    }

    // 3. Monta o HTML do Balão (message-bubble)
    // REMOVIDO: qualquer tag extra (como <p>) que possa vir do broadcast
    // GARANTIDO: o conteúdo é injetado diretamente como no seu HTML.erb
    const bubbleHtml = `
      <div class="message-bubble">${escapeHtml(message.content)}</div>
    `;

    // 4. Junta tudo e insere no chat
    el.innerHTML = avatarHtml + bubbleHtml;

    chatWindow.appendChild(el);
    scrollToBottom();
  }

  
  // =======================================================
  //   FUNÇÕES ÚTEIS
  // =======================================================
  function escapeHtml(str) {
    if (!str) return "";
    return str.replace(/[&<>'"]/g, (c) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]));
  }

  function scrollToBottom() {
    chatWindow.scrollTop = chatWindow.scrollHeight;
  }

  // =======================================================
  //   AJUSTE DE TECLADO (iOS)
  // =======================================================
  // O iOS Safari desloca o document quando o teclado abre, mesmo dentro de
  // position:fixed. Ajustamos o wrapper diretamente ao visualViewport para
  // garantir que header + mensagens + input caibam na área visível real.

  const chatWrapper = document.querySelector('.chat-screen-wrapper');

  function adjustToViewport() {
    if (!chatWrapper || !window.visualViewport) return;
    const vv = window.visualViewport;
    chatWrapper.style.height = vv.height + 'px';
    chatWrapper.style.top    = vv.offsetTop + 'px';
    requestAnimationFrame(scrollToBottom);
  }

  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', adjustToViewport);
    window.visualViewport.addEventListener('scroll', adjustToViewport);
  }

  // Dispara imediatamente ao abrir a página — sem esperar o teclado
  adjustToViewport();
  requestAnimationFrame(() => { adjustToViewport(); scrollToBottom(); });

  // Fallback para dispositivos sem visualViewport (Safari antigo)
  messageInput.addEventListener('focus', () => setTimeout(scrollToBottom, 380));

  // Restaura dimensões originais ao fechar o teclado
  messageInput.addEventListener('blur', () => {
    if (chatWrapper) {
      chatWrapper.style.height = '';
      chatWrapper.style.top    = '';
    }
    requestAnimationFrame(scrollToBottom);
  });
});