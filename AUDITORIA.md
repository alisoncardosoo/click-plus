# Auditoria funcional — 9 de novembro de 2026

## Resultado

Não há confirmação de funcionamento completo de todos os recursos. A versão revisada compila e passa em **33 testes automatizados**. Estes testes validam lógica e isolamento com eventos simulados, não substituem os testes físicos.

| Função | Evidência / estado |
| --- | --- |
| Permissões e serviço | Acessibilidade e Monitoramento de Entrada permitidos na interface real; serviço ativo. |
| Identificar M650 Bluetooth | Confirmado no dispositivo e na interface. |
| Bateria e DPI atuais | Leituras reais: 45% e 1200 DPI. Consultas de DPI tiveram falha transitória anteriormente. |
| Aplicar/restaurar DPI físico | Implementado com leitura após escrita. Não exercitado: preservado o DPI atual; depende de escolha explícita no app. |
| Cadastrar/remover/recadastrar botão | Confirmado fisicamente pelo usuário e pela interface. Cadastro HID++ funciona mesmo quando CGEvent não identifica o mouse. |
| Lateral 1 → LaunchOS | Confirmado pelo usuário. |
| Lateral 2 → Mission Control | Confirmado pelo usuário após chamada direta ao aplicativo do sistema. |
| Apertar novamente para ocultar aplicativo | Confirmado pelo usuário no LaunchOS. Painel LaunchOS é fechado com Escape dirigido ao seu processo; outros apps usam ocultar e retorno ao anterior. Não encerra processos. |
| Abrir/fechar Mission Control | Usuário confirmou abertura e fechamento pelo botão, com chamada nativa ao app do sistema. |
| Clique da roda → ChatGPT | Configuração salva pelo usuário; execução física não confirmada separadamente. |
| Voltar/avançar, copiar/colar, atalhos | Implementados como teclas/modificadores; entrega de ações validada em testes. Resultado depende do atalho e do aplicativo em foco. Sem aceite físico individual. |
| Curva, duração, frenagem e suavização | Curva normalizada testada em múltiplas configurações. Rolagem suave 1,5× confirmada pelo usuário nesta rodada; 17 eventos de rolagem transformados. Todas as combinações de curva não foram experimentadas individualmente. |
| Velocidade, aceleração e inversões de rolagem | Transformações testadas; execução física de rolagem observada em sessão anterior. Aceite de todas as combinações pendente. |
| Shift + roda / eixo horizontal | Transformação e retirada do modificador testadas. Aceite físico pendente. |
| Control + roda / zoom | Seleção da tecla e modificadores testada; zero movimento não produz zoom. Aceite em aplicativo real pendente. |
| Command + roda / ganho | Multiplicação e remoção do modificador testadas. Aceite físico pendente. |
| Cursor: velocidade, aceleração zero e tecla temporária | Velocidade real 1,3× confirmada pelo usuário e por 241 movimentos transformados; diagnóstico confirmou aceleração isolada no serviço do mouse. Tecla temporária testada em lógica; múltiplos monitores ainda não exercitados. |
| Trackpad | Usuário confirmou trackpad normal com velocidade/rolagem do mouse ativas. Contadores: 274 eventos do trackpad preservados. Testes automatizados também excluem trackpad durante pan HID++. |
| Pan: clique versus arrasto | Testes comprovam clique único, ausência de clique após arrasto e exclusão do arrasto de outro botão. |
| Pan físico e inércia | Corrigido para receber pressionamento/soltura dos laterais por HID++ e processar somente movimento identificado do M650. Usuário confirmou arrasto com rolagem e clique curto abrindo a função original, com inércia ligada. Cursor parado e todos os eixos/modificadores ainda sem aceite individual. |
| Trazer janela à frente / click-through | Implementação AX inspecionada; depende de suporte do aplicativo. Sem validação completa em janela inativa. |
| Sliders por rolagem | Implementação AX inspecionada, fallback para rolagem quando não ajustável. Corrigida seleção do eixo em movimento diagonal. Teste físico de controles externos pendente. |
| Pausa e perda de permissão | Filtro de pausa testado; suspensão da engine e restauração HID na perda de permissão corrigidas. Transição física de permissões não exercitada nesta auditoria. |
| Reconexão e repouso | Caminhos de cancelamento/restauração/reinicialização implementados. Sem teste físico completo. |
| Logi Bolt | Descoberta conservadora implementada; nenhum teste físico de Bolt confirmado. |
| Persistência local | Round-trip automatizado e preferências reais preservadas entre builds. |
| Iniciar com macOS | Usuário habilitou; estado exibido ativo. Login/reinício real não testado. |
| Dock, barra de menus e janela | Interface nativa aberta e Dock condicionado à janela implementado. Sem novo ciclo completo de fechar/reabrir nesta auditoria. |

## Correções desta revisão

- Alternância de aplicativos: abre ou oculta o app em foco, lembrando o aplicativo anterior; sem encerrar o programa.
- Pan não reage mais a arrasto de um botão diferente do selecionado.
- Zoom ignora movimento zero e permite teste sem injetar teclado no desktop.
- Slider horizontal usa o eixo habilitado quando há movimento diagonal.
- Clique interrompendo inércia também limpa resíduos fracionários anteriores.
- Perda de Acessibilidade suspende o processamento; perda de Monitoramento de Entrada interrompe a captura HID.

## Medições e limites

- Bundle Debug: aproximadamente 2,0 MB.
- Amostra com janela aberta após iniciar: 131 MiB de memória residente e 5,8% CPU. Não é benchmark de repouso nem conclusão sobre consumo contínuo.
- Não houve push, publicação, atualização de firmware, alteração de pareamento ou escrita de DPI nesta auditoria.
- Na janela de teste físico desta revisão, os contadores permaneceram zerados: não houve evidência de movimentos/rolagens para validar cursor e trackpad nesta etapa. Valores temporários foram restaurados: cursor desativado/1× e rolagem desativada/1×/sem suavização; mapeamentos e início com macOS preservados.
- A consulta periódica exibiu bateria 45% com DPI não confirmado depois de uma leitura de 1200. Corrigida a mensagem para distinguir falha parcial de consulta de ausência total de resposta; estabilidade de DPI permanece pendente.

## Aceite físico posterior à auditoria inicial

- Usuário respondeu “tudo ok” ao teste de velocidade 1,3×, rolagem suave 1,5×, preservação do trackpad e fechamento do LaunchOS. UI confirmou 260 eventos M650, 241 movimentos ajustados, 17 rolagens transformadas e 274 eventos de trackpad preservados.
- Usuário confirmou pan e clique curto. Ao final escolheu manter a configuração atual de pan: **Lateral dianteiro**, com inércia ligada. Preservados os mapeamentos LaunchOS, Mission Control e ChatGPT.
- Personalização de cursor e rolagem permanecem ligadas nos valores aprovados, diferentemente da rodada anterior de teste sem entrada física.
- Build final e 33 testes aprovados. Bolt, escrita/restauração de DPI, retorno físico do repouso e múltiplos monitores permanecem sem aceite específico; não são declarados validados por esta rodada.
