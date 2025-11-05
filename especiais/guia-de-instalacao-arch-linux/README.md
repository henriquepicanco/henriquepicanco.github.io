# Guia (pessoal) de instalação do Arch Linux

Um guia (pessoal) de instalação do Arch Linux com BTRFS encriptado, EFIstub como bootloader e mais.

>[!CAUTION]
>Este guia é extremamente opinioso, ou seja, totalmente pensado e escrito para as minhas necessidades. Use-o como base para criar algo seu, fazendo um *fork* ou, se ele servir ao que você busca no Arch Linux, sinta-se livre para usá-lo.

>[!WARNING]
>Seguir este guia, sem saber o que está sendo feito, pode trazer perda de dados e até dano irreversível a outros conteúdos presentes em seus discos (desde além de perda de arquivos ao apagamento completo de outros sistemas operacionais). Use-o por sua conta e risco.

## Instalação

### Pré-instalação

#### Layout do teclado e fonte do console

Primeiro, configuramos o layout do teclado para o seu teclado atual (no meu caso, `us-acentos`) e definimos a fonte do console para *eurlatgr*, que suporta caracteres latinos.

```text
# loadkeys us-acentos
# setfont eurlatgr
```

#### Verificar se estamos em UEFI

```text
# cat /sys/firmware/efi/fw_platform_size
```

O resultado deve dar `64`. Se der outro resultado, reinicie o sistema em modo UEFI.

#### Checar conexão com a internet

No ambiente live, quando conectado via cabo, a conexão é automática. Caso precise de Wi-Fi, rode `iwctl`. Depois, verifique se a conexão está estável, rodando:

```text
# ping ping.archlinux.org -c 4
```

#### Atualizar o relógio do sistema

O sistema irá atualizar o relógio no momento em que uma conexão com a internet for identificada. Para certificar-se, rode:

```text
# timedatectl
```

#### Particionar os discos

Primeiro, checamos o disco onde será instalado.

```text
# fdisk -l
```

Anote o disco onde será instalado. Substitua `sda`, nesta e em outras entradas através deste guia de instalação, pelo identificador do seu disco (ex: /dev/sda, /dev/nvme0n1, etc.)

Então, particionamos o disco:

```text
# gdisk /dev/sdX
```

Caso ainda não tenha limpado o disco onde iremos instalar o sistema, o faça.

>[!WARNING]
>Todos os dados no disco selecionado serão apagados. Verifique se está particionando o disco correto antes de prosseguir.

```text
z
w
```

Primeiro, criamos a tabela de partição GPT.

```text
o
y
```

Depois, criamos a partição para `/efi`, onde ficará nossa *[imagem unificada de kernel (UKI)](https://wiki.archlinux.org/title/UKI)*:

```text
n
[ENTER]
[ENTER]
+1G
EF00
```

E então, a partição onde ficarão nosso conteúdos encriptados:


```text
n
[ENTER]
[ENTER]
[ENTER]
8309
```

O código `8309` define a partição como “Linux LUKS” conforme a especificação GPT. É opcional, mas ajuda ferramentas de disco a identificarem corretamente o tipo.

Por fim, escrevemos as mudanças no disco:

```text
w
y
```

Com isto, teremos duas partições. `/dev/sdX1` onde ficará o *bootloader* e `/dev/sdX2` onde ficará o sistema. Em seguida, podemos criar a encriptação.

```text
# cryptsetup --hash sha512 --use-random --sector-size 4096 luksFormat /dev/sdX2
# cryptsetup open /dev/sdX2 cryptroot
```

Na sequencia, formatamos as nossas partições.

```text
# mkfs.fat -F 32 /dev/sdX1
# mkfs.btrfs /dev/mapper/cryptroot
```

Em seguida, montamos a partição BTRFS para criar nossos subvolumes.

```text
# mount /dev/mapper/cryptroot /mnt
# btrfs su cr /mnt/@
# btrfs su cr /mnt/@home
# btrfs su cr /mnt/@pkg
# btrfs su cr /mnt/@flatpak
# btrfs su cr /mnt/@machines
# btrfs su cr /mnt/@portables
# btrfs su cr /mnt/@log
# btrfs su cr /mnt/@.snapshots
# umount /mnt
```

Com os subvolumes criados, podemos prosseguir para a montagem dos subvolumes e da partição de boot. Note que a partir do segundo comando `mount`, a flag `-m` é adicionada. Esta *flag* garante que a pasta de destino (no caso `/mnt/home`) seja criada no momento em que o subvolume (ou partição) é montado.

```text
# mount /dev/mapper/cryptroot -o rw,relatime,compress=zstd:7,space_cache=v2,subvol=@ /mnt
# mount /dev/mapper/cryptroot -m -o rw,relatime,compress=zstd:7,space_cache=v2,subvol=@home /mnt/home
# mount /dev/mapper/cryptroot -m -o rw,relatime,nodatacow,space_cache=v2,subvol=@pkg /mnt/var/cache/pacman/pkg
# mount /dev/mapper/cryptroot -m -o rw,relatime,nodatacow,space_cache=v2,subvol=@flatpak /mnt/var/lib/flatpak
# mount /dev/mapper/cryptroot -m -o rw,relatime,compress=zstd:7,space_cache=v2,subvol=@machines /mnt/var/lib/machines
# mount /dev/mapper/cryptroot -m -o rw,relatime,compress=zstd:7,space_cache=v2,subvol=@portables /mnt/var/lib/portables
# mount /dev/mapper/cryptroot -m -o rw,relatime,nodatacow,space_cache=v2,subvol=@log /mnt/var/log
# mount /dev/mapper/cryptroot -m -o rw,relatime,compress=zstd:7,space_cache=v2,subvol=@.snapshots /mnt/.snapshots
# mount /dev/sdX1 -m -o rw,relatime,umask=0077,utf8,errors=remount-ro /mnt/efi
```

### Instalação

#### Editar pacman.conf

Edite o conteúdo de `/etc/pacman.conf`, para que fique semelhante ao conteúdo abaixo. Este arquivo será copiado, mais tarde, para o nosso sistema instalado pelo `pacstrap`.

```text
# vim /etc/pacman.conf
----------------------
[options]
HoldPkg = pacman glibc
Architecture = auto

UseSyslog
Color
CheckSpace
VerbosePkgLists
ParallelDownloads = 5
DownloadUser = alpm
DisableDownloadTimeout

SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
```

#### Editar o mirrorlist

Por padrão, o `reflector` criará um mirrorlist genérico, porém efetivo para um sistema rápido. Prefiro, entretanto, editar o arquivo para que dê preferência a espelhos do Arch Linux no Brasil, nos Estados Unidos e espelhos internacionais.

```text
# vim /etc/pacman.d/mirrorlist
-------------------------------
# UFPR
Server = https://archlinux.c3sl.ufpr.br/$repo/os/$arch

# UFSCAR
Server = https://mirror.ufscar.br/archlinux/$repo/os/$arch

# UNICAMP
Server = https://mirrors.ic.unicamp.br/archlinux/$repo/os/$arch

# Kernel.org
Server = https://mirrors.edge.kernel.org/archlinux/$repo/os/$arch

# Rackspace
Server = https://iad.mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://ord.mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://dfw.mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch

# Leaseweb
Server = https://mirror.wdc1.us.leaseweb.net/archlinux/$repo/os/$arch
Server = https://mirror.sfo12.us.leaseweb.net/archlinux/$repo/os/$arch

# PKGBUILD
Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
```

#### Instalar o sistema

No comando `pacstrap` abaixo, o `-K` significa que iremos iniciar um keyring do pacman no sistema a ser instalado e o `P` (que pode ser entendido como `-P`) irá copiar o `/etc/pacman.conf` que editamos anteriormente para esta instalação.

Use `intel-ucode` (ou `amd-ucode`, se seu processador for AMD) para incluir as microatualizações de CPU.

Neste comando, usarei expansão por chaves para evitar repetições de nomes (`linux` e ter que repetir "linux" em `linux-firmware`, por exemplo).

```text
# pacstrap -KP /mnt base linux{,-firmware} intel-ucode btrfs-progs efibootmgr networkmanager openssh neovim sudo man-{db,pages}
```

### Configurando o sistema

#### Gerar `fstab`

```text
# genfstab -U /mnt >> /mnt/etc/fstab
```

Depois, podemos editar o `/etc/fstab`. Isto não é necessário, mas a vida é feita de teimosias. Gosto de editar este arquivo para ficar semelhante ao conteúdo abaixo, apenas por estética.

```text
# vim /mnt/etc/fstab
--------------------
# FILESYSTEM                               PATH                   TYPE   OPTIONS                                                        DUMP  PASS
# /dev/mapper/cryptroot
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /                      btrfs  rw,relatime,compress=zstd:7,space_cache=v2,subvol=@            0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /home                  btrfs  rw,relatime,compress=zstd:7,space_cache=v2,subvol=@home        0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /var/cache/pacman/pkg  btrfs  rw,relatime,nodatacow,space_cache=v2,subvol=@pkg               0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /var/lib/flatpak       btrfs  rw,relatime,nodatacow,space_cache=v2,subvol=@flatpak           0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /var/lib/machines      btrfs  rw,relatime,compress=zstd:7,space_cache=v2,subvol=@machines    0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /var/lib/portables     btrfs  rw,relatime,compress=zstd:7,space_cache=v2,subvol=@portables   0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /var/log               btrfs  rw,relatime,nodatacow,space_cache=v2,subvol=@log               0     0
UUID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  /.snapshots            btrfs  rw,relatime,compress=zstd:7,space_cache=v2,subvol=@.snapshots  0     0
# /dev/sdX1
UUID=XXXX-XXXX                             /efi                   vfat   rw,relatime,umask=0077,utf8,errors=remount-ro                  0     2
```

#### Chroot

Agora, iremos fazer configurações diretamente no nosso sistema instalado, através da ferramenta `arch-chroot`.

```text
# arch-chroot /mnt
```

#### Relógio

Primeiro, fazendo um *link* do arquivo que aponta nosso fuso-horário para o arquivo `/etc/localtime`. Troque `America/Sao_Paulo` pelo fuso que lhe for mais conveniente.

```text
# ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
```
Em seguida, configuramos para que o sistema configure o relógio do *hardware* em UTC.

```text
# hwclock --systohc
```

Depois, abrimos o arquivo `/etc/systemd/timesyncd.conf` e, neste arquivo, editamos o conteúdo para ficar semelhante ao seguinte:

```text
nvim /etc/systemd/timesyncd.conf
--------------------------------
[Time]
NTP=0.br.pool.ntp.org 1.br.pool.ntp.org 2.br.pool.ntp.org 3.br.pool.ntp.org
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
```

#### Localização

Primeiro, substituiremos o conteúdo do arquivo `/etc/locale.gen` para ficarmos apenas com os *locales* relevantes.

```text
# nvim /etc/locale.gen
----------------------
pt_BR.UTF-8 UTF-8
en_US.UTF-8 UTF-8
```

Na sequencia, podemos gerar os *locales* com o comando:

```text
# locale-gen
```

Após, iremos adicionar a linha `LANG=pt_BR.UTF-8` ao arquivo `/etc/locale.conf`. Este arquivo ainda não existe, mas será criado ao o editarmos. Como iremos adicionar uma única linha ao arquivo, podemos criar este arquivo com o comando echo.

```text
# echo LANG=pt_BR.UTF-8 > /etc/locale.conf
```

Por último, iremos criar o arquivo `/etc/vconsole.conf`, que irá espelhar nossas configuracões feitas nos comandos `loadkeys` e `setfont` no início do guia para o sistema instalado.

```text
# nvim /etc/vconsole.conf
-------------------------
KEYMAP=us-acentos
FONT=eurlatgr
```

#### Configuração de rede

Adicionamos um nome único para o nosso computador.

```text
# echo seu-hostname > /etc/hostname
```

>[!TIP]
>Como dica para criar um nome único, verifique [RFC 1178](https://tools.ietf.org/html/rfc1178). Recomenda-se algo entre 1 e 63 caracteres em caixa baixa, entre `a-z`, `0-9` e `-`, mas não pode começar com um `-`.

Em seguida, editamos o arquivo `hosts`.

```text
# nvim /etc/hosts
-----------------
# IPv4
127.0.0.1 localhost
127.0.1.1 seu-hostname.localdomain seu-hostname

# IPv6
::1 localhost ip6-localhost ip6-loopback
fa02::1 ip6-allnodes
fa02::2 ip6-allrouters
```

#### Configurar sudo

Podemos configurar o `sudo` do sistema com uma mudança não destrutiva, criando o arquivo `00-wheel` em `/etc/sudoers.d/`. Isto permitirá que usuários do grupo `wheel` possam rodar comandos como superusuário.

```text
# echo "%wheel ALL=(ALL:ALL) ALL" | EDITOR=tee visudo -f /etc/sudoers.d/00-wheel
```

#### Usuários e root

Primeiro, criaremos o usuário que terá permissões de superusuário através de `sudo` no nosso sistema.

```text
# useradd -m -c "Nome completo" -G wheel -s /bin/bash usuario
```

Criaremos agora uma senha segura para este usuário. Esta senha deve ser longa, recomendado ter pelo menos 8 caracteres que misture letras em caixas alta e baixa, símbolos e números.

```text
# passwd usuario
```

Por último, iremos **bloquear o acesso de root**. Esta é uma medida de segurança popular. Vale lembrar que anteriormente configuramos o `sudo` e na criação do nosso usuários, o colocamos no grupo `wheel`, que terá permissão de superusuário para tarefas e funções típicas de root.

```text
# passwd -l root
```

#### Serviços

O comando abaixo habilitará os serviços de vários componentes, para que iniciem juntamente com o computador ao ligar. Novamente, usarei expansão por chaves do Bash para evitar repetição de muitas palavras (como os timers do btrfs-scrub).

```text
# systemctl enable {NetworkManager,sshd,systemd-{timesyncd,oomd,resolved}}.service {fstrim,btrfs-scrub@{-,home,pkg,flatpak,machines,portables,log,\\x2esnapshots}}.timer
```

#### Configurando o mkinitcpio

Nesta instalação usaremos EFIstub, que é uma forma do UEFI inicializar o sistema carregando diretamente o kernel Linux. Ou seja, **não precisamos de um bootloader**. Entretanto, algumas configurações são importantes para que isto funcione.

Primeiro, apagamos resquícios do método anterior de configuração do initramfs, pois usaremos [UKI](https://wiki.archlinux.org/title/UKI) nesta instalação.

```text
# rm /boot/initramfs-linux*
```

Depois, editamos o arquivo de configuracão do `mkinitcpio`.

```text
# nvim /etc/mkinitcpio.conf
---------------------------
MODULES=()
BINARIES=()
FILES=()
HOOKS=(systemd autodetect microcode modconf kms keyboard sd-vconsole sd-encrypt block filesystems)
```

Em seguida, criamos os parâmetros do kernel para serem passados diretamente ao arquivo UKI. Entretanto, a pasta onde estes arquivos irão residir ainda não existem. Primeiro, criaremos `/etc/cmdline.d`.

```text
# mkdir -p /etc/cmdline.d
```

Depois, criaremos os quatro arquivos numerados que usaremos para o cmdline. De início, o `rd.luks.name` que armazena o UUID da partição onde fica o contêiner LUKS.

```text
# echo "rd.luks.name=$(blkid -s UUID -o value /dev/sdX2)=cryptroot" > /etc/cmdline.d/00-luks.conf
```

Depois, o parâmetro `root` que indica onde reside os sistema de arquivos do root. Neste caso, aponta para o mapeamento do nosso contêiner LUKS.

```text
# echo "root=/dev/mapper/cryptroot" > /etc/cmdline.d/01-root.conf
```

Em `02-rootflags.conf`, apontamos o root do sistema para o mapeamento do contêiner LUKS.

```text
# echo "rootflags=subvol=@" > /etc/cmdline.d/02-rootflags.conf
```

E adicionamos alguns outros parâmetros comuns ao kernel.

```text
# echo "rw loglevel=3 quiet splash" > /etc/cmdline.d/03-parameters.conf
```

Por último, alguns parâmetros relacionados ao *splas screen*. O *splah screen* será uma tela com a logo do Arch Linux que será exibida durante a inicialização do sistema, evitando mostrar textos do systemd nesta etapa.

```text
# echo "quiet splash" > /etc/cmdline.d/04-splash.conf
```

Abrimos o arquivo de configuração da criação do UKI em `/etc/mkinitcpio.d/linux.preset`. Neste arquivo, modificamos o parâmetros de criação do UKI.

```text
# nvim /etc/mkinitcpio.d/linux.preset
-------------------------------------
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"

fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
```

Se tentarmos gerar o initramfs agora, o mkinitcpio dará erro. Isso por conta da pasta `/efi/EFI/Linux` ainda não existir. Podemos criá-la com o comando:

```text
# mkdir -p /efi/EFI/Linux
```

Então, geramos o ramdisk inicial. Ela criará o UKI em /efi/EFI/Linux, tanto o principal quanto o *fallback*.

```text
# mkinitcpio -P
```

#### EFIstub

Após a criação dos UKIs do sistema, é preciso adicionar entradas ao nosso UEFI para identificar o caminho da nossa imagem unificada. Faremos isto com o comando `efibootmgr`, e criaremos entradas tanto para o UKI principal quando para o *fallback*.

```text
# efibootmgr --create --disk /dev/sdX --part 1 --label "Arch Linux" --loader '\EFI\Linux\arch-linux.efi'
# efibootmgr --create --disk /dev/sdX --part 1 --label "Arch Linux (Fallback)" --loader '\EFI\Linux\arch-linux-fallback.efi'
```

Após criado, convém organizar a ordem de inicialização, que pode estar completamente fora de ordem e até mesmo com o *fallback* tendo prioridade sobre a imagem principal. Ao criarmos as entradas, o `efibootmgr` já irá mostrar o número correspondente da entrada que criamos numa sequencia de 4 algarismos (algo como `0001`, `0002`, etc.)

Para organizar as entradas, rode o comando abaixo. Troque `000X` pelo número correspondende a entrada `Arch Linux` e 000Y pelo número correspondende ao `Arch Linux (Fallback)`:

```text
# efibootmgr --bootorder 000X,000Y
```

### Finalizando

O sistema está agora instalado e pronto para ser usado. Podemos terminar esta etapa com os comandos a seguir.

Saímos do ambiente chroot digitando o comando abaixou ou usando a sequencia `CTRL + D` no teclado.

```text
# exit
```

Desmontamos todas as partições onde o sistema foi instalado.

```text
# umount -R /mnt
```

Fechamos o contêiner LUKS com `cryptsetup`.

```text
# cryptsetup close cryptroot
```

E reiniciamos imediatamente. Você também pode somente desligar o computador para continuar posteriormente, trocando `reboot` por `poweroff` no comando abaixo.

```text
# systemctl reboot
```

## Pós-instalação

### Configuração do ambiente de trabalho

#### Git

Vamos instalar e configurar o Git de forma que a configuração do programa fique em *$XDG_CONFIG_HOME*.

```text
$ sudo pacman -S git
$ mkdir -p ~/.config/git
$ touch ~/.config/git/config
$ git config --global user.name "Henrique Picanço"
$ git config --global user.email "114828539+henriquepicanco@users.noreply.github.com"
$ git config --global init.defaultBrach main
```

#### Stow

O **GNU stow** é um utilitário para gerir *dotfiles*.

```text
$ sudo pacman -S stow
```

### Pacotes adicionais ao sistema-base

#### NVIDIA

Para instalar o drive da NVIDIA, primeiro adicionaremos um parâmetro de kernel ao `/etc/cmdline.d`. Ele será adicionado a uma nova imagem unificada de kernel, que será gerada automaticamente ao instalarmos o driver.

```text
$ echo "nvidia_drm.modeset=1" | sudo tee /etc/cmdline.d/50-nvidia.conf
$ sudo pacman -S nvidia-open lib32-nvidia-utils
```

#### Flatpak

Com Flatpaks, podemos ter programas sempre atualizados de forma isolada do sistema operacional, assim gerando mais segurança (e menos chances de dar algum problema com o Arch Linux).

```text
$ sudo pacman -S flatpak
$ sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

### Ambiente, fontes, áudio e programas

#### Fontes

Instalaremos algumas fontes para termos uma ampla gama de caracters visíveis, como emojis.

```text
$ sudo pacman -S {gnu-free,noto}-fonts ttf-{bitstream-vera,croscore,dejavu,droid,ibm-plex,input{,-nerd},liberation,roboto}
```

#### Áudio

O Pipewire e o WirePlumber serão instalados e, depois, ativaremos os serviços respecitovs a nível de usuário (não podem ser ativados a nível de sistema).

```text
$ sudo pacman -S pipewire-{alsa,jack,pulse} wireplumber
$ systemctl enable --user {pipewire{,-pulse},wireplumber}.service
```

#### Bluetooth

Instalaremos os utilitários de bluetooth e ativar o serviço do systemd.

```text
$ sudo pacman -S bluez{,-utils}
$ sudo systemctl enable bluetooth.service
```

#### Ambiente gráfico

```text
$ sudo pacman -S greetd{,-tuigreet} niri alacritty rofi-wayland waybar mako nautilus
$ sudo systemctl enable greetd.service
```

#### Programas

Nesta lista, o Firefox, Thunderbird, VLC, Zed, Visual Studio COde, Flatseal, GNOME Text Editor, 

```text
$ sudo flatpak install org.mozilla.{firefox,Thunderbird} org.videolan.VLC dev.zed.Zed com.visualstudio.Code com.github.tchx84.Flatseal org.gnome.TextEditor com.valvesoftware.Steam org.libreoffice.LibreOffice org.nickvision.tubeconverter
```
