// Fotos do chat (painel do "+": Fotos e Câmera).
//
// preparePhoto: a foto da câmera do celular tem vários MB — antes de enviar ela é
// reduzida (lado maior até 1600px) e vira JPEG. Sai já girada do jeito certo: o
// navegador aplica a orientação da câmera ao desenhar a imagem.
//
// createPhotoViewer: a foto do balão aberta em tela cheia.

const MAX_SIDE = 1600;
const QUALITY  = 0.84;
const ACCEPTED = ["image/jpeg", "image/png", "image/webp"]; // o que o servidor aceita sem conversão
const MAX_ORIGINAL_SIZE = 10 * 1024 * 1024;

function loadImage(url) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("imagem ilegível"));
    image.src = url;
  });
}

// → { blob, width, height }. Rejeita quando o arquivo não é uma imagem que dê para enviar.
export async function preparePhoto(file) {
  const url = URL.createObjectURL(file);

  try {
    const image  = await loadImage(url);
    const scale  = Math.min(1, MAX_SIDE / Math.max(image.naturalWidth, image.naturalHeight));
    const width  = Math.max(1, Math.round(image.naturalWidth * scale));
    const height = Math.max(1, Math.round(image.naturalHeight * scale));

    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    context.fillStyle = "#fff"; // PNG com transparência não vira fundo preto no JPEG
    context.fillRect(0, 0, width, height);
    context.drawImage(image, 0, 0, width, height);

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", QUALITY));
    if (!blob) throw new Error("não foi possível converter");

    return { blob, width, height };
  } catch (error) {
    // O navegador não conseguiu abrir a imagem para reduzir: se o formato é aceito e o
    // tamanho cabe, vai o arquivo original
    if (ACCEPTED.includes(file.type) && file.size <= MAX_ORIGINAL_SIZE) {
      return { blob: file, width: 0, height: 0 };
    }
    throw error;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function createPhotoViewer() {
  let viewer = null;

  function close() {
    if (!viewer) return;
    viewer.hidden = true;
    viewer.querySelector("img").removeAttribute("src");
  }

  function build() {
    viewer = document.createElement("div");
    viewer.className = "chat-photo-viewer";
    viewer.hidden = true;
    viewer.setAttribute("role", "dialog");
    viewer.setAttribute("aria-label", "Foto");
    viewer.innerHTML =
      `<button type="button" class="chat-photo-viewer-close" aria-label="Fechar">` +
        `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>` +
      `</button>` +
      `<img alt="Foto">`;
    viewer.addEventListener("click", close); // tocar em qualquer lugar fecha
    document.body.appendChild(viewer);
  }

  return {
    open(src) {
      if (!src) return;
      if (!viewer || !viewer.isConnected) build();
      viewer.querySelector("img").src = src;
      viewer.hidden = false;
    },
    close,
    isOpen: () => !!viewer && !viewer.hidden
  };
}
