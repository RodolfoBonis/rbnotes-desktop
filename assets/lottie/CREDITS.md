# Animações Lottie

- **pulse.json** — autoral (criado para o RbNotes). Um pulso em acento `#E0512E`
  (anel que expande/esmaece + ponto central). Usado em momentos de sucesso/vazio:
  - onboarding "Tudo pronto" (sob o botão de gravar);
  - estado vazio de "Tarefas esquecidas" ("Nada esquecido").

Por ser autoral, não há licença de terceiros. Caso um asset do LottieFiles seja
adicionado no futuro, registrar aqui a fonte e a **Lottie Simple License (FL 9.13.1)**.

As demais animações do app são feitas em Flutter puro (sem Lottie): onda ao vivo
(`LiveWaveBars`), pulso do ponto REC (`PulseDot`), typewriter/streaming do título e
das respostas (revelação incremental de texto), transições dos HUDs/overlays
(fade+scale) e seleção de lista/abas. Todas respeitam "Reduzir movimento"
(`MediaQuery.disableAnimations`).
