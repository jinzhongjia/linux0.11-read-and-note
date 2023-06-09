;
; SYS_SIZE is the number of clicks (16 bytes) to be loaded.
; 0x3000 is 0x30000 bytes = 196kB, more than enough for current
; versions of linux
;
SYSSIZE = 0x3000
;
;	bootsect.s		(C) 1991 Linus Torvalds
;
; bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
; iself out of the way to address 0x90000, and jumps there.
;
; It then loads 'setup' directly after itself (0x90200), and the system
; at 0x10000, using BIOS interrupts. 
;
; NOTE; currently system is at most 8*65536 bytes long. This should be no
; problem, even in the future. I want to keep it simple. This 512 kB
; kernel size should be enough, especially as this doesn't contain the
; buffer cache as in minix
;
; The loader has been made as simple as possible, and continuos
; read errors will result in a unbreakable loop. Reboot by hand. It
; loads pretty fast by getting whole sectors at a time whenever possible.

; TODO: 这里各段定义还没搞懂

; 此处定义的是全局对外暴漏的字段，text，data,bss的开始和结束，这里几个段定义的起始地址都是一样的
.globl begtext, begdata, begbss, endtext, enddata, endbss
.text
begtext:
.data
begdata:
.bss
begbss:
.text

; 定义常量
SETUPLEN = 4				; nr of setup-sectors
BOOTSEG  = 0x07c0			; original address of boot-sector
INITSEG  = 0x9000			; we move boot here - out of the way
SETUPSEG = 0x9020			; setup starts here
SYSSEG   = 0x1000			; system loaded at 0x10000 (65536).
ENDSEG   = SYSSEG + SYSSIZE		; where to stop loading

; ROOT_DEV:	0x000 - same type of floppy as boot.
;		0x301 - first partition on first drive etc
ROOT_DEV = 0x306

; 内存地址存储方式，基址:偏移地址，计算方式为基址左移四位（注意是二进制左移四位），设计成这样的原因是因为当时的地址线不够用，就这样设计了，具体可以自行去查找原因

; 定义了入口
entry start
start:
	mov	ax,#BOOTSEG
	mov	ds,ax
	mov	ax,#INITSEG
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	; 这里循环执行复制，每次一个字，从ds:si 到es:di 处，共复制256次,也就是复制了256个字,这里一个字是两个字节，16位，刚好将初始化读取的512个字节从#BOOTSEG复制到了#INITSEG
	rep
	movw
	jmpi go,INITSEG ;jmpi 是段间跳转指令
	; 这里的作用是跳转到go标签处的偏移地址，也就是INITSEG + go处继续执行，刚好可以跳过上面逻辑，完美！

; 在这里定义go执行后面的逻辑，start执行完后会通过上方的jmpi跳转到这里继续执行，到这里时就已经完成了boot的512字节复制功能
; 注意：这里的cs是代码段寄存器，存放的是代码段基址，所以现在cs是0x9000
; 一下go的逻辑就是为了设置运行时需要的堆栈空间,堆栈是从高地址到地地址发展，设置的够高防止发生碰撞
go:	mov	ax,cs
	; ds是数据段寄存器，存放数据段基址，这里也把0x9000塞进去
	mov	ds,ax
	; es是附加段寄存器，存放附加段基址，也是0x9000
	mov	es,ax
; 接下来设置堆栈的范围，这里选区的地址是0x9ff00，注意下方是0xFF00，这只是偏移地址
; put stack at 0x9ff00.
	; ss是栈段寄存器
	mov	ss,ax
	; sp是栈基址寄存器,和ss（左移四位后）相加才变成栈地址,所以目前栈顶才是0x9FF00
	mov	sp,#0xFF00		; arbitrary value >>512
	; 到这里结束，已经设置完了数据段、代码段、堆栈段的地址（准确来说只是堆栈顶部的指针）

; load the setup-sectors directly after the bootblock.
; Note that 'es' is already set up.

load_setup:
	; 下面四个寄存器指定应该是指定的读取数据在硬盘开始位置和读取的数据大小
	mov	dx,#0x0000		; drive 0, head 0 dh是磁头号，dl是要进行读操作的驱动器号
	mov	cx,#0x0002		; sector 2, track 0 ch是磁道号的低8位数，cl是低5位放入所读起始扇区号，位7-6表示磁道号的高2位
	mov	bx,#0x0200		; address = 512, in INITSEG
	; bx指向数据缓冲区,这里是数据段的偏移地址，但是为何是512呢，因为前512已经被我们用过了，还记得上面执行过一次从#BOOTSEG复制到#INITSEG共512字节的函数吗
	mov	ax,#0x0200+SETUPLEN	; service 2, nr of sectors ah为调用的服务种类，这里是service2,al是读取的扇区数目
	; 这里的是为了出发0x13号中断，上面设置ax、bx、cx、dx,仅仅是传递参数进去
	int	0x13			; read it 调用软中断，这里是intel定义的，不过通用，调用的是0x13软中断，为读中断
	jnc	ok_load_setup		; ok - continue 成功的话就跳转到ok_load_setup继续执行
	mov	dx,#0x0000
	mov	ax,#0x0000		; reset the diskette 这里是如果失败了先进行清空软盘的操作
	int	0x13
	j	load_setup

ok_load_setup:

; Get disk drive parameters, specifically nr of sectors/track

	mov	dl,#0x00
	mov	ax,#0x0800		; AH=8 is get drive parameters ; 这里ax为ah为08是指获取磁盘信息
	int	0x13
	mov	ch,#0x00
	seg cs ; 这里表示操作数在cs段寄存器所指的段中
	mov	sectors,cx ; 保存磁道的扇区数
	mov	ax,#INITSEG
	mov	es,ax ; 重新覆盖回es的值，上面执行的操作破坏了es

; Print some inane message ; 这里准备打印一些消息来提示用户

	mov	ah,#0x03		; read cursor pos
	xor	bh,bh ; 按位逻辑异或,一个数和它自己本身进行逻辑异或操作，实际效果为清零
	int	0x10 ; 触发屏幕打印中断
	
	mov	cx,#24
	mov	bx,#0x0007		; page 0, attribute 7 (normal)
	mov	bp,#msg1
	mov	ax,#0x1301		; write string, move cursor
	int	0x10 ; 触发屏幕打印中断

; ok, we've written the message, now
; we want to load the system (at 0x10000)

; 此处就是读取磁盘加载系统到内存中的代码
	mov	ax,#SYSSEG
	mov	es,ax		; segment of 0x010000
	call	read_it
	call	kill_motor

; After that we check which root-device to use. If the device is
; defined (!= 0), nothing is done and the given device is used.
; Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
; on the number of sectors that the BIOS reports currently.

	seg cs
	mov	ax,root_dev
	cmp	ax,#0
	jne	root_defined
	seg cs
	mov	bx,sectors
	mov	ax,#0x0208		; /dev/ps0 - 1.2Mb
	cmp	bx,#15
	je	root_defined
	mov	ax,#0x021c		; /dev/PS0 - 1.44Mb
	cmp	bx,#18
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	seg cs
	mov	root_dev,ax

; after that (everyting loaded), we jump to
; the setup-routine loaded directly after
; the bootblock:

	jmpi	0,SETUPSEG

; 以下就是子程序了这里就直接跳转走了

; This routine loads the system at address 0x10000, making sure
; no 64kB boundaries are crossed. We try to load it as fast as
; possible, loading whole tracks whenever we can.
;
; in:	es - starting address segment (normally 0x1000)
;
sread:	.word 1+SETUPLEN	; sectors read of current track
head:	.word 0			; current head
track:	.word 0			; current track

read_it:
	mov ax,es
	test ax,#0x0fff
die:	jne die			; es must be at 64kB boundary
	xor bx,bx		; bx is starting address within segment
rp_read:
	mov ax,es
	cmp ax,#ENDSEG		; have we loaded all yet?
	jb ok1_read
	ret
ok1_read:
	seg cs
	mov ax,sectors
	sub ax,sread
	mov cx,ax
	shl cx,#9
	add cx,bx
	jnc ok2_read
	je ok2_read
	xor ax,ax
	sub ax,bx
	shr ax,#9
ok2_read:
	call read_track
	mov cx,ax
	add ax,sread
	seg cs
	cmp ax,sectors
	jne ok3_read
	mov ax,#1
	sub ax,head
	jne ok4_read
	inc track
ok4_read:
	mov head,ax
	xor ax,ax
ok3_read:
	mov sread,ax
	shl cx,#9
	add bx,cx
	jnc rp_read
	mov ax,es
	add ax,#0x1000
	mov es,ax
	xor bx,bx
	jmp rp_read

read_track:
	push ax
	push bx
	push cx
	push dx
	mov dx,track
	mov cx,sread
	inc cx
	mov ch,dl
	mov dx,head
	mov dh,dl
	mov dl,#0
	and dx,#0x0100
	mov ah,#2
	int 0x13
	jc bad_rt
	pop dx
	pop cx
	pop bx
	pop ax
	ret
bad_rt:	mov ax,#0
	mov dx,#0
	int 0x13
	pop dx
	pop cx
	pop bx
	pop ax
	jmp read_track

/*
 * This procedure turns off the floppy drive motor, so
 * that we enter the kernel in a known state, and
 * don't have to worry about it later.
 */
kill_motor:
	push dx
	mov dx,#0x3f2
	mov al,#0
	outb
	pop dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55

.text
endtext:
.data
enddata:
.bss
endbss:
