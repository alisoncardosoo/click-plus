# Validação

## Ambiente

- Mac arm64, macOS reportado pelo host: 27.3.
- Xcode / Swift 6.4.2; deployment target macOS 14.
- Logitech M650 L detectado no registro I/O por Bluetooth Low Energy.

## Verificações realizadas

- Build Debug: aprovado.
- Abertura do app e inspeção das telas Rolagem, Mouse e Botões via acessibilidade: aprovado.
- Padrões desativados na primeira abertura: confirmado.
- Dez testes: isolamento de eventos sintéticos, rejeição de origem USB desconhecida, padrões de captura, curva normalizada em múltiplas configurações, linearidade com aceleração zero, persistência, lista/faixa de DPI, pacote HID++ e modificadores: aprovados.
- Primeira consulta HID: o macOS negou `IOHIDDeviceOpen` por permissão TCC. Não representa ausência de suporte do mouse.

## Aceite físico ainda necessário

- Confirmar permissões na versão assinada e leitura real de bateria/DPI.
- Aplicar um DPI permitido, ler de volta e restaurar o anterior.
- Comparar rolagem suave, inversão, modificadores, zoom, botões e pan em aplicativos reais.
- Confirmar cursor linear, múltiplos monitores e independência do trackpad em uso alternado e simultâneo.
- Confirmar slider acessível, fallback e click-through em janelas inativas.
- Repetir com Bolt, incluindo identidade do serviço de entrada. Não declarar suporte completo ao Bolt enquanto essa identificação não for comprovada.
- Validar repouso, desconexão e recuperação.

Os testes automatizados não substituem o aceite físico. Não foi comprovada paridade com BetterMouse.

## Verificação final da versão assinada

- Assinatura Apple Development local verificada; identificador `br.com.ratoesperto.app`.
- Interface de Ajustes informa Acessibilidade **Pendente** e Monitoramento de Entrada **Pendente** na última inspeção. O usuário havia habilitado a compilação temporária anterior; a versão assinada ainda precisa receber essas permissões.
- Teste real da interface: ativar Personalizar rolagem habilitou sliders; alterar Duração de 0,16 para 0,30 atualizou o valor e a duração do gráfico para 300 ms. Os valores foram restaurados ao fim do teste.
- Tamanho do `.app` Debug: aproximadamente 1,5 MB.
- Amostra em repouso da compilação Debug: cerca de 107 MB de memória residente e 0,6% de CPU; é uma amostra, não um benchmark. Uso durante processamento físico ainda não medido.
- Sem push, publicação ou alterações de DPI durante a implementação.

## Correção do registro de permissões

- Os logs de TCC mostraram referência à cópia removida em `build-test` e incompatibilidade entre o cdhash da assinatura temporária e a assinatura Apple Development.
- Removido o registro antigo do Launch Services e registrado novamente o bundle principal. Resetados somente Accessibility e ListenEvent de `br.com.ratoesperto.app` com `tccutil`.
- O script de execução agora registra explicitamente o bundle principal depois do build.
- Após o procedimento e a interação do usuário, a interface confirmou **Acessibilidade: Permitida**. Monitoramento de Entrada ainda estava pendente na última observação.

## Leitura física confirmada — Bluetooth

Na inspeção da interface após concessão das permissões:

- Acessibilidade: Permitida.
- Monitoramento de Entrada: Permitido.
- Dispositivo: Logi M650 L, Bluetooth Low Energy.
- Após clicar Consultar dispositivo, o app apresentou DPI atual **1200** e bateria **45%**, com mensagem de resposta HID++ confirmada.
- Nenhuma escrita de DPI foi realizada. A leitura inicial de DPI estava indisponível e foi obtida ao atualizar a consulta; estabilidade das consultas periódicas ainda requer observação.
- Isso confirma leitura por Bluetooth; não valida escrita/restauração de DPI nem o receptor Bolt.

## Cadastro físico de botões e isolamento de eventos

- Adicionado Adicionar botão: captura somente clique da roda ou botões extras do M650 identificado; consome pressionamento/soltura e abre um editor de função. Cancelamento, perda de foco e timeout encerram a captura. Capturar um botão já cadastrado reutiliza a entrada.
- Salvar a função habilita automaticamente a captura do botão. A lista acompanha as atribuições salvas e permite removê-las.
- Suite ampliada para 19 testes, todos aprovados: ciclo completo de captura, cancelamento sem soltura órfã, exclusão de cliques principais/trackpad, atribuição sem duplicação, ação disparada uma vez na soltura, transformação de rolagem e Shift, velocidade/modificador e eventos de trackpad preservados com todas as personalizações ligadas.
- Os testes de transformação usam eventos e identificação de origem simulados, sem injetar entrada no desktop. Não equivalem a teste físico.
- Incluídos contadores locais por execução em Ajustes para acompanhar origem física, ações, rolagens e movimentos transformados; sem registro de teclas/conteúdo.
- No teste físico, o usuário relatou que os laterais não executavam as funções. Contadores anteriores mostraram 85 transformações de rolagem, 299 eventos de trackpad preservados e zero ações de botões/transformações do cursor. Isso não confirma a experiência física do trackpad nem o controle do cursor.
- Restaurados os ajustes temporários pela interface: rolagem desativada, velocidade 1x, suavização desligada; cursor desativado e velocidade 1x. Preservados mapeamentos e inicialização automática escolhidos pelo usuário.

## Recuperação de botões desviados — Bluetooth

- Consulta real HID++ REPROG_CONTROLS_V4, índice 8: controles 0x0053 (tarefa 0x003C) e 0x0056 (tarefa 0x003E) apresentavam flag de desvio temporário 0x01. Portanto não enviavam cliques HID normais. Não é possível atribuir com certeza qual programa deixou esse estado.
- Implementado comando explícito “Restaurar cliques nativos do mouse”. Consulta as capacidades; remove apenas desvio temporário de tarefas de botão central/voltar/avançar identificadas, preservando flags persistentes e remapeamentos. Não altera DPI, firmware nem pareamento. Não há sobrescrita periódica de configurações de outros programas.
- Executado no dispositivo: leitura após escrita confirmou dois botões restaurados. A interface apresentou “Modo nativo confirmado. Botões restaurados: 2.”
- Build aprovado e 20 testes passaram, incluindo escopo de recuperação e rejeição de respostas de outro controle.
- Solicitado novo teste físico de Mission Control e cadastro por pressionamento; execução final ainda depende da confirmação do usuário.

## Recadastro por HID++ — confirmação física

- Usuário confirmou Mission Control funcionando após restaurar os cliques nativos, mas o cadastro por CGEvent continuava falhando.
- Diagnóstico durante tentativa física: otherMouseDown/Up dos botões 3 e 4 chegaram com senderID 0 e origem desconhecida. O filtro recusou corretamente esses eventos; não foi flexibilizado para aceitar origem ambígua.
- Cadastro agora consulta REPROG_CONTROLS_V4 do M650, habilita desvio temporário apenas nos controles de botão central/voltar/avançar anunciados pelo dispositivo e identifica a soltura através das notificações HID++ do dispositivo, endereço e feature esperados. Restaura flags anteriores com leitura após escrita ao detectar, cancelar, expirar, dormir ou encerrar.
- Build aprovado, 23 testes aprovados, incluindo parsing de controles HID++, lista pressionada/solta e recadastro após remoção.
- Na interação real do usuário, a interface voltou da captura e exibiu **Botão lateral 1 → Abrir aplicativo → LaunchOS**. Confirma cadastro físico e salvamento do botão removido; não confirma, por si, a execução do LaunchOS ao pressionar posteriormente.

## Execução das funções por HID++

- Estendida a leitura direta aos botões com funções atribuídas e captura habilitada. Somente controles anunciados pelo M650 e notificações da interface/endereço/feature selecionados executam ações na soltura; eventos CGEvent de origem desconhecida continuam preservados.
- Sessões têm identificador para rejeitar notificações atrasadas após troca de configuração. Pausa, saída, suspensão e perda de Acessibilidade restauram o modo anterior. Retorno do repouso/reconexão prepara novamente os controles; esses cenários ainda requerem aceite físico.
- Botões em Original e o botão selecionado para pan ficam no caminho nativo. Pan de eventos sem identificação ainda é uma limitação, não validada por esta correção.
- Build e 25 testes aprovados, incluindo entrega da ação de aplicativo com caminho correto e exclusão de botões pausados, removidos, desabilitados ou reservados ao pan.
- Logs físicos registraram botão 3 → LaunchOS duas vezes e botão 4 → Mission Control. A interface agora mostra “Último acionamento” para esclarecer a correspondência. O usuário relatou função diferente da esperada; solicitada confirmação do outro lateral. Janela do LaunchOS observada separadamente via inspeção do app, o que não é prova isolada de abertura pelo mouse.
- Erros de abertura de aplicativo agora são exibidos ao usuário.

## Ação Mission Control sem dependência do atalho

- Usuário confirmou que o lateral 1 abre o LaunchOS. Relatou que o lateral 2 não abria Mission Control.
- Logs confirmaram repetidos eventos HID++ do botão 4 com ação Mission Control, descartando perda da atribuição nessa tentativa.
- Substituído envio de Control + seta acima pela abertura de `/System/Applications/Mission Control.app`, existente no host. Reutilizado o mesmo tratamento de erro de abertura de aplicativos; o mapeamento LaunchOS foi preservado.
- Os 25 testes passaram e a compilação atualizada foi aberta pelo script. Solicitada confirmação física da visão de janelas com o lateral 2.
- Aceite físico recebido do usuário após a atualização: **“os dois funcionaram”**. Confirmados lateral 1 abrindo LaunchOS e lateral 2 abrindo Mission Control nesta conexão Bluetooth.

## Auditoria geral

Ver `AUDITORIA.md` para a matriz de todos os controles, evidências e pendências. Nesta revisão: 31 testes passaram; corrigidos pan com botão incorreto, zoom com delta zero, eixo de sliders diagonais, limpeza de resíduos e suspensão após perda de permissão. Implementada alternância abrir/ocultar aplicativos em foco com retorno ao anterior, sem encerrá-los. Aceite físico da alternância ainda pendente.

A janela de teste de velocidade/rolagem não registrou eventos físicos; ajustes temporários restaurados. Não confundir ausência de entrada no teste com aprovação física. Leitura parcial de bateria/DPI agora tem mensagem específica. Build final aprovado e app aberto.

## Correções e teste físico de velocidade, rolagem e pan

- Corrigido fechamento LaunchOS: app acessório recusa `hide()`. Escape agora é enviado exclusivamente ao PID do LaunchOS em foco, seguido do retorno ao app anterior se necessário. Usuário confirmou funcionamento.
- Pan lateral agora usa estados pressionado/solto HID++, sem tentar adivinhar origem de CGEvent. Movimento só transforma quando identificado como M650. Testes cobrem pan, clique curto e exclusão do trackpad.
- 33 testes passaram e build foi aberto. Usuário confirmou “tudo ok” para cursor 1,3×, rolagem suave 1,5×, trackpad e alternância do LaunchOS. Contadores: 241 movimentos transformados, 17 rolagens, 274 eventos de trackpad preservados; aceleração isolada no serviço do mouse.
- Usuário confirmou teste de pan e pediu manter sua escolha atual: lateral dianteiro com inércia. Cursor/rolagem ficaram ligados nos valores aprovados. Ver AUDITORIA.md para limites restantes de validação por transporte.

## Português e ajuda dos controles

- Pan virou “Arrastar para rolar”; click-through virou “Clicar em janela inativa”; sliders viraram “controles deslizantes”; zoom virou “Ampliar ou reduzir”. Mission Control aparece como “Visão de janelas”, com nome original explicado na ajuda. Menus nativos agora usam português.
- Botões de interrogação abrem explicações clicáveis sobre curva, velocidade, aceleração, inércia, modificadores, DPI, ações e janelas inativas; fechar pelo botão Entendi confirmado na interface real.
- Build aprovado e app atualizado aberto. Valores serializados de ações/modificadores mantidos para preservar os mapeamentos existentes; nenhum comportamento de eventos foi alterado nesta etapa.

## Bateria do teclado e menu superior

- Teclado Logi K950 conectado por Bluetooth; consulta HID++ real confirmou **100%**, exibido na seção Mouse. M650 L exibiu **45%**.
- Menu do ícone da barra de menus agora apresenta nome/bateria do mouse e teclados Logitech detectados, atualização ao abrir e opção Atualizar baterias. Usuário confirmou que as duas linhas aparecem.
- Teclados têm leitura de bateria separada da identificação e do processamento de eventos do mouse. Apenas consultas de capacidades/bateria; não mapeia teclas nem altera o teclado. Sem bateria confirmada, exibe indisponibilidade, sem estimar porcentagens.
- 34 testes passaram, incluindo validação de limites da porcentagem e rejeição de booleanos; build final aprovado.

## Melhoria estética da interface

- Hierarquia visual com cabeçalhos por seção, identidade teal e baterias compactas na barra lateral.
- Controles numéricos em linha, valores destacados, curva com preenchimento/grade e ajustes detalhados agrupados em expansores.
- Ajuda e configurações existentes preservadas; mudanças limitadas à interface. Build aprovado e inspeção visual das telas Rolagem e Mouse realizada na janela real.

## Dispositivos separados e gestos de borda do trackpad

- Navegação separada em Mouse, Teclado, Trackpad e Ajustes. Mouse reúne abas Ponteiro e sensor, Rolagem e Botões; bateria Logitech passou para Teclado.
- Gestos do trackpad integrado via MultitouchSupport com verificação de símbolos e layout de contato. Ativação explícita no app, pausa global, perda de permissões, repouso e encerramento cancelam o reconhecimento e removem callbacks.
- Cada borda permite desligar ou escolher brilho, volume, trocar faixas, reproduzir/pausar e ações personalizadas para cada direção. Atalhos e abertura de aplicativos usam o editor de ações existente. Toque curto para reproduzir/pausar é opcional na borda inferior.
- Um dedo deve iniciar em borda habilitada e passar do limiar. Centro, mudança de dedo, coordenadas inválidas, saída da faixa e vários dedos não executam ações. Faixas e ações personalizadas limitadas a uma execução por contato. Movimento/rolagem só é suprimido em eventos identificados como trackpad durante gesto reconhecido; eventos desconhecidos preservados.
- 45 testes passaram (11 novos de reconhecimento/persistência/cancelamento). Build final aprovado.
- Serviço informou trackpad integrado pronto. Após teste físico solicitado de brilho/volume e centro/dois dedos, usuário confirmou: “sim, esta tudo funcionando e normal”. A interface também registrou Inferior • Trocar faixas; não confirma por si a resposta de todo aplicativo de mídia.
- Usuário personalizou as bordas na interface: esquerda Brilho, direita Volume, inferior Trocar faixas, superior Desativado. Mantidas as escolhas e gestos ativados. Configuração salva em trackpad.v1, separada dos ajustes do mouse.
- APIs multitouch são não públicas; suporte a trackpad externo e todos os players não é declarado. Nenhuma mudança de permissão ou preferência global do macOS foi feita.

## Renomeação para Click +

- Interface, menu do app, pacote .app, projeto Xcode, módulo Swift, arquivos, pasta de fontes, documentação e configuração Run renomeados.
- Pasta principal: `/Volumes/SSD/Projetos/Click +`; caminho anterior mantido como link para preservar a referência desta conversa.
- Mantido o identificador de assinatura/preferências `br.com.ratoesperto.app`. Interface confirmou ambas as permissões concedidas e inicialização automática ligada após a mudança.
- App renomeado compilado e aberto, com ícone lilás, preferências de velocidade/botões e baterias preservadas. Registro Launch Services do bundle gerado anterior removido.
- Nome do projeto na barra lateral do Codex não alterado: não há ferramenta de renomeação de projeto disponível e o acesso UI ao próprio Codex foi bloqueado por segurança. Necessária alteração manual nessa superfície.

## Painel da barra de menus em lilás

- Menu padrão substituído por painel nativo compacto de 330 pontos, com marca Click +, estado ativo/pausado e botão de ativação.
- Mouse e teclado têm linhas visuais próprias, porcentagens grandes e barras proporcionais em lilás. Carga baixa usa laranja; ausência de leitura exibe traço e explicação, sem porcentagem simulada.
- Mantidos Configurações e Sair. Atualização automática ao abrir e a cada 30 segundos; sem botão de atualização manual.
- Build aprovado e app aberto. Solicitado ao usuário abrir o painel para aceite visual; inspeção da janela principal realizada, painel ainda sem confirmação visual nesta etapa.

## Ampliação para dispositivos Logitech — 10/11/2026

- Removida dependência do nome M650 da detecção de entrada: fabricante e uso HID qualificam o mouse, com seleção explícita por identidade física. Rejeitados teclado, dispositivos compostos ambíguos, trackpad, dispositivos virtuais e receptor genérico sem verificação.
- Descoberta lista modelos e conexões. Nome vem do produto HID ou leitura HID++ do dispositivo emparelhado. Seletor de mouse permite alternar modelos; troca cancela estados e restaura DPI anterior quando controlado. Configurações globais preservadas.
- Recursos avançados continuam sujeitos à confirmação: DPI 0x2201, bateria do sistema/0x1000/0x1004, captura 0x1B04. Cadastro usa evento nativo identificado como alternativa. Receptores podem fornecer modelo pela tabela de pareamento; múltiplos apontadores ambíguos não recebem transformação de movimento.
- Respostas HID++ agora são filtradas também pelo dispositivo de origem, além de endereço/feature/software ID. Desconectar um teclado não cancela desnecessariamente o mouse.
- 50 testes aprovados; novos testes usam descritores simulados de famílias MX, G, M e ERGO, e rejeitam teclados, trackpads, receptores genéricos e dispositivos virtuais. Isso não é aceite físico desses modelos.
- Build final aprovado e app aberto. Nesta execução não há Logitech conectado para comprovar modelo real. Usuário informou não ter outro dispositivo para teste. Modelos confirmados fisicamente permanecem M650 L e K950 de sessões anteriores.

## Release pública 0.1.0 e instalação — 10/11/2026

- README atualizado para repositório público, clonagem sem autenticação e instalação pelo pacote de release. Licença permanece não definida.
- Versão 0.1.0, build 1, configurada em project.yml e projeto Xcode regenerado. Script package_release.sh compila em Release para arm64 e x86_64, valida assinatura/arquiteturas e gera ZIP com SHA-256 em dist/.
- 50 testes passaram. Build Release universal aprovado e assinatura Apple Development validada por codesign --verify --deep --strict. Sem Developer ID ou notarização; não há garantia de aceitação pelo Gatekeeper em outro Mac. Execução Intel não validada fisicamente.
- ZIP extraído e instalado em /Applications/Click +.app. Executável instalado com SHA-256 idêntico ao build Release. Processo confirmado nesse caminho e interface real inspecionada: M650 L, K950, velocidade 1,3, captura lateral e inicialização com o macOS preservados; Acessibilidade exibida como permitida.
- Verificação desta etapa confirma instalação e abertura; não substitui novo aceite físico de todos os controles ou da sensação háptica.


## Bluetooth — 10/11/2026

- Consulta local `system_profiler SPBluetoothDataType -json`, fora da thread principal, sem conectar ou parear acessórios. Atualização a cada 30 segundos e ao abrir o menu; consulta manual na área Bluetooth.
- Somente `device_connected` alimenta a interface. Níveis principal, esquerdo, direito e estojo são opcionais e validados entre 0 e 100; falhas limpam leituras anteriores. Mouse/teclado Logitech continuam com suas leituras HID++.
- 54 testes passaram, incluindo quatro novos testes de interpretação, dispositivos desconectados, deduplicação, bateria ausente e percentuais inválidos.
- Consulta física identificou Galaxy Buds 2 de Alison como pareado e desconectado. A leitura de bateria desse fone permanece sem validação física; depende dos dados expostos pelo macOS.


## Avisos de bateria — 10/11/2026

- Notificações locais via UserNotifications, ativação explícita em Ajustes, limites iniciais de 20% e 5%, limites configuráveis e som opcional. Preferências e histórico de avisos persistem localmente.
- Leituras do mouse selecionado, teclados e componentes Bluetooth alimentam os alertas. Níveis inválidos são ignorados; ausências não apagam o histórico. Uma primeira leitura crítica gera somente o aviso crítico; nova rodada exige recarga confirmada acima do limite baixo com margem contra oscilações.
- Build Debug e abertura via `./script/build_and_run.sh --verify` aprovados; 58 testes passaram, incluindo limites personalizados, deduplicação, independência entre dispositivos, recarga e persistência do histórico. Tela Ajustes inspecionada com os controles de ativação, 20%, 5% e som.
- Não foi enviada notificação real nem concedida permissão pelo usuário nesta validação. O recurso permanece inicialmente desativado; a entrega de um banner real depende da autorização e das configurações do macOS.

## Altura da lista no menu — 10/11/2026

- A lista de baterias passou a reservar altura conforme a quantidade de dispositivos/componentes, limitada a 440 pontos. Evita depender da altura ideal de um ScrollView com apenas maxHeight dentro do MenuBarExtra.
- Build Debug e reabertura via `./script/build_and_run.sh --verify` aprovados. Mouse M650 L (45%) e teclado K950 (100%) confirmados na janela principal. A superfície da barra de menus não ficou acessível à automação; a exibição no popover ainda precisa de confirmação visual.


## Galaxy Buds2 — bateria por lado — 10/11/2026

- Implementada recepção passiva de status Samsung pelo serviço RFCOMM `2e73a4ad-332d-41fc-90e2-16bef06523f2`, somente para Buds2 já conectado e pareado. Consulta assíncrona com prazo de 5 segundos; fecha o canal ao obter status ou falhar. Não envia comandos. Se falhar, mantém a alternativa do relatório macOS.
- Parser valida enquadramento e CRC16-CCITT, aceita callbacks fragmentados/concatenados e ignora mensagens que não sejam status `0x60`/`0x61`.
- Leitura física inicial: esquerdo 100%, direito 100%. Após compilar e abrir a versão atualizada, a interface Bluetooth foi inspecionada: **Esquerdo: 99% · Direito: 100%** no Galaxy Buds 2 de Alison. O estojo não informou um nível utilizável nessa consulta.
- 63 testes passaram, incluindo cinco novos testes de protocolo com captura real, integridade, fragmentação, limites e escopo de modelo. Build e abertura confirmados por `./script/build_and_run.sh --verify`.
- Referência dos campos do protocolo: https://github.com/timschneeb/GalaxyBudsClient/blob/master/GalaxyBudsClient/Message/Decoder/ExtendedStatusUpdateDecoder.cs e `StatusUpdateDecoder.cs` no mesmo diretório. Implementação Swift própria, sem dependência desse cliente.


## Estojo e menu de dispositivos conectados — 10/11/2026

- A consulta Samsung agora acumula status por até 5 segundos quando a primeira mensagem não contém bateria válida do estojo, incluindo mensagens concatenadas no mesmo callback. Encerra antes se receber o estojo. Não simula porcentagem nem gera leitura/alerta para os valores de indisponibilidade 0, 101 ou 255.
- Estojo sem leitura tem indicação explícita na área Bluetooth e no menu, orientando a abrir a tampa com um fone dentro. A porcentagem física do estojo permaneceu indisponível na consulta desta validação; a interface exibiu esquerdo 99%, direito 100% e “Bateria não informada” para o estojo.
- Menu remove os placeholders de mouse/teclado desconectados e dimensiona sua lista conforme as linhas visíveis. A lista Bluetooth descarta acessórios desconectados antes da consulta Samsung e verifica novamente a conexão ao concluir.
- 65 testes passaram, com cobertura adicional da mensagem tardia do estojo e valores de indisponibilidade. Build e abertura local passaram; interface Bluetooth inspecionada.


## Correção da captura do estojo em tempo real — 10/11/2026

- Substituída a consulta Samsung de 5 segundos por uma sessão de status RFCOMM mantida enquanto o Buds2 está conectado. Novos status atualizam imediatamente a interface; o refresh de 30 segundos reconcilia a lista e tenta recuperar sessões encerradas. A sessão é fechada no shutdown e quando o dispositivo deixa a lista de conectados. Nenhum comando é enviado.
- A captura física do estojo informou 99%. Novo teste usa essa captura real e valida esquerdo 98%, direito 99%, estojo 99%.
- **Validação física na versão atualizada:** interface Bluetooth mostrou “Esquerdo: 100% · Direito: 100% · Estojo: 99%”. Assim, a porcentagem do estojo foi efetivamente conferida na tela; a validação anterior de indisponibilidade não demonstrava o funcionamento físico.
- 66 testes passaram. Build e abertura da versão atualizada confirmados com `./script/build_and_run.sh --verify`.


## Última bateria do estojo ao fechar a tampa — 10/11/2026

- Histórico em memória por endereço Bluetooth mantém apenas o último nível válido do estojo e sua data/hora. Quando o status deixa de informar o estojo, a interface continua mostrando esse nível como “Última leitura”. Uma nova medição limpa a marcação histórica e substitui o valor. Histórico limitado à execução atual do app; dispositivos desconectados continuam ocultos.
- Leituras históricas não entram na avaliação de alertas de bateria, evitando tratar informação anterior como nova medição.
- 69 testes passaram. Três novos testes validam preservação da porcentagem e do horário, substituição pela próxima leitura, indisponibilidade sem histórico e isolamento entre dispositivos. A sequência física de abrir/fechar a tampa não foi repetida nesta etapa.


## Release 0.2.0 (build 2) — 10/11/2026

- 69 testes passaram após atualizar a versão. Pacote Release universal (arm64/x86_64) compilado e assinatura Apple Development verificada. O pacote continua sem notarização.
- Instalado o mesmo binário do pacote em `/Applications/Click +.app`; versão 0.2.0, build 2, hash SHA-256 do executável idêntico ao artefato de Release. A instalação anterior foi preservada em backup temporário recuperável, sem alterar preferências.
- Processo da instalação em Aplicativos confirmado; interface e área Bluetooth abertas e inspecionadas. Na verificação de instalação não havia outro periférico Bluetooth conectado, então não foi repetida a leitura física do estojo nessa etapa. As leituras físicas de Buds2 estão registradas acima.
