# Charcoal SteamOS Kernel

[English](README.md)

O Charcoal é um kernel personalizado para SteamOS, mantido neste repositório. O objetivo desta fork é preservar os recursos de desempenho, scheduler, gerenciamento de memória e hardware no próprio kernel, removendo ajustes de userspace voltados a jogos e o pacote de drivers/workarounds de controles de terceiros que não são necessários para esses recursos.

**Este repositório é a origem do instalador e das releases.** O instalador deve buscar pacotes de `Marctraider/linux-charcoal-vulcano`, não do repositório original `zarpon/linux-charcoal-vulcano`.

## Intenção desta fork em relação ao projeto original de Zarpon

Este repositório começou como uma fork de [linux-charcoal-vulcano de Zarpon](https://github.com/zarpon/linux-charcoal-vulcano). Mantém a ideia geral de um kernel SteamOS focado em desempenho, mas separa de forma mais clara os recursos do kernel dos ajustes opcionais do sistema e da sessão de jogos.

| Área | Intenção desta fork |
|---|---|
| Scheduler e reclaim | Manter BORE, POC Selector, ADIOS, LRU CAST e NAP. |
| Memória e compressão | Manter ZSWAP e ZRAM-IR no kernel, incluindo a integração udev/runtime necessária para ZRAM-IR e ADIOS. |
| Gerenciamento de energia AMD | Manter AMD P-State EPP em modo active e os ajustes de EPP boost. |
| Steam Deck / Van Gogh | Manter os patches de frequência/limite de potência Van Gogh e as alterações IOMMU selecionadas. |
| Compilador e CPU | Manter alvo Zen 2, Clang/LLVM, O3, Full Clang LTO e Polly. |
| Ajustes de userspace para jogos | Remover perfis sysctl personalizados, variáveis de ambiente forçadas e migração/configuração de swapfile. |
| Drivers de controles | Remover o pacote xone, xpadneo e xpad-noone e seus workarounds. O Steam Input não é removido. |

Em resumo: **os recursos do kernel permanecem; políticas opcionais de sessão de jogos e workarounds de controles não são impostos pelo pacote.** Isso não garante mais FPS ou menor latência em todos os jogos.

A fork também avançou em relação à base de kernel antiga do projeto original. O pipeline mantido aqui resolve a imagem SteamOS stable atual e a fonte/configuração Valve correspondente, em vez de simplesmente compilar o snapshot antigo.

## Instalação da release desta fork

Use SteamOS Stable e execute no Modo Desktop. Mantenha um método de recuperação disponível. No Steam Deck, siga as instruções de configuração IOMMU/BIOS do projeto antes de instalar se pretende usar essas alterações.

**Importante:** o instalador baixa pacotes pré-compilados. Ele não compila o kernel no Steam Deck. É necessário existir uma release estável publicada neste repositório. Se a página de [Releases desta fork](https://github.com/Marctraider/linux-charcoal-vulcano/releases) ainda não tiver uma release estável, aguarde a primeira execução de publicação bem-sucedida.

Quando houver uma release estável, execute:

```bash
curl -fsSL https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/master/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

O instalador consulta a [última release desta fork](https://github.com/Marctraider/linux-charcoal-vulcano/releases/latest), não as releases de Zarpon.

### O que o instalador faz

1. Consulta a última release estável, sem rascunhos ou prereleases, deste repositório.
2. Baixa o ZIP e o checksum SHA-256 da release por HTTPS.
3. Verifica o ZIP, extrai com segurança o kernel e os headers correspondentes e confere os hashes individuais.
4. Consulta os metadados dos pacotes antes de iniciar a transação.
5. Identifica kernels Charcoal anteriores e o kernel SteamOS original conflitante da mesma série. A remoção do kernel original exige confirmação.
6. Pede confirmação antes de alterar pacotes, habilita modo de escrita/desenvolvedor, instala kernel e headers verificados e atualiza o bootloader.
7. Tenta rollback usando cópias exatas no cache do pacman se a instalação falhar e todos os pacotes removidos estiverem disponíveis no cache.

O instalador nunca reinicia automaticamente. Não reinicie se a instalação falhar e o rollback não estiver disponível. Leia os prompts antes de confirmar.

Após instalar com sucesso, reinicie manualmente e execute:

```bash
uname -r
pacman -Q | grep '^linux-charcoal'
sudo charcoal-status
```

O kernel em execução deve identificar a série Charcoal instalada. O `charcoal-status` diferencia configuração compilada de ativação em execução. `[PASS]` indica sucesso, `[WARN]` indica algo que exige contexto (por exemplo, reinicialização ou hardware) e `[FAIL]` indica falha em uma verificação obrigatória.

Variáveis opcionais:

- `CHARCOAL_72_REMOVE_STOCK=1`: autoriza previamente a remoção do kernel original conflitante.
- `CHARCOAL_72_ASSUME_YES=1`: aceita as duas confirmações.

Use essas opções somente se compreender as alterações autorizadas.

## Recursos do kernel mantidos

A configuração e os patches mantêm as versões selecionadas de BORE/sched_ext, POC Selector, ADIOS, LRU CAST, NAP, ZRAM-IR, ZSWAP, AMD P-State EPP boost, alvo Zen 2, Clang/LLVM, O3, Full Clang LTO, Polly e os patches Van Gogh/IOMMU selecionados.

As regras udev de ADIOS e ZRAM-IR e os hooks de ciclo de vida do NAP permanecem. O ZSWAP do kernel é diferente da configuração de swap userspace voltada a jogos que foi removida.

### O que foi removido intencionalmente

Foram removidos perfis sysctl personalizados para jogos, variáveis de ambiente, scripts de migração/configuração de swapfile, unidades systemd relacionadas e o pacote de drivers/workarounds xone, xpadneo e xpad-noone.

O Steam Input é um recurso userspace do Steam e não é removido. O suporte efetivo a controles ainda depende da configuração do kernel, do dispositivo e do userspace do SteamOS.

## Observações de desempenho e segurança

- O3, LTO e Polly não garantem mais FPS ou menor latência; os resultados dependem do hardware e da carga.
- Os patches Van Gogh elevam limites configurados de frequência/potência, mas não garantem que o hardware mantenha esses valores.
- O caminho IOMMU PerfOpt pode pular ATS/PRI/PASID/SVA em GPUs integradas AMD elegíveis e usar um caminho DMA identity otimizado. Isso reduz o isolamento DMA daquele dispositivo. Entenda essa consequência de segurança antes de usar.
- CI e validações de pacote não substituem testes reais de boot, suspensão/retomada, Wi-Fi, áudio, controles e jogos no Steam Deck.

## Como o build acompanha o SteamOS stable

A fonte de verdade é o [metadata oficial de atualização stable da Valve](https://steamdeck-atomupd.steamos.cloud/meta/holo/steamos/amd64/steamdeck/stable.json). O resolvedor seleciona uma imagem marcada explicitamente como stable, baixa o manifesto de pacotes correspondente, identifica o pacote `linux-neptune-<série>` exato e resolve a fonte/tag/configuração Valve correspondente.

Imagens preview/main e kernels RC/beta são rejeitados. Metadados ausentes ou ambíguos fazem o build falhar, sem fallback silencioso. A imagem, manifesto, URL da fonte, tag e série ficam registrados em `steamos-stable-source.json`.

A compatibilidade dos patches é verificada contra essa fonte. Famílias obrigatórias não são removidas ou rebaixadas silenciosamente quando APIs mudam. O `patch-lock.json` registra versões, origens, hashes e recursos já fornecidos pelo upstream Valve.

## Build e publicação

A branch `master` é a branch destinada às releases estáveis.

- Pushes em `master` executam o build e o workflow de publicação.
- Pull requests e builds `validation/**` validam alterações, mas não publicam releases.
- O workflow diário acompanha a fonte SteamOS stable e compila a `master`.
- A release só é publicada após validação de fontes/patches, configuração, compilação, empacotamento e checksums.
- As releases incluem kernel, headers correspondentes, ZIP, checksums, patch-lock e metadados da fonte estável.

A workflow `kernel-7.2` permanece para builds manuais de desenvolvimento e artefatos; não é o caminho de release estável.

Para desenvolvimento local, o fluxo de preparação usa Python 3, Bash e Git:

```bash
python3 automation/prepare-pkgbuild-7.2.py --write PKGBUILD
python3 automation/prepare-steamos-stable.py --fetch-config
python3 automation/resolve-latest-patches-7.2-policy.py --overrides logs/patch-source-overrides-stable.json --write
python3 automation/validate-patch-lock.py --manifest logs/patch-sources-7.2.json --overrides logs/patch-source-overrides-stable.json
```

O Dockerfile fornece o ambiente Arch Linux/LLVM. Validação CI não garante funcionamento em todas as revisões de hardware.

## Detalhes da configuração

O padrão ZSTD genérico da Crypto API é nível 1, inclusive para zswap genérico. Isso é separado do modo fast próprio do ZRAM-IR e dos backends Intel QAT.

As alterações mantidas de `CONFIG_ZEN_INTERACTIVE` limitam-se ao comportamento existente de RCU assíncrono evdev e seleção schedutil P-State; esta fork não importa um conjunto amplo de padrões Zen não relacionados.

O aprendizado do NAP persiste entre reinicializações, com salvamentos periódicos. O pacote inclui `napctl` e o visualizador offline `/usr/share/nap/napviz.html`, gerado a partir do modelo do kernel compilado. Consulte [NAP-TOOLS.md](NAP-TOOLS.md).

## Escopo

Este é um projeto de kernel experimental para entusiastas do SteamOS, não um kernel oficial da Valve nem uma distribuição Linux de uso geral. Mantenha um método de recuperação, leia os prompts do instalador e preserve uma opção de boot conhecida e funcional sempre que possível.
