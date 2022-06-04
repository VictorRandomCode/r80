# frozen_string_literal: true

require 'minitest/autorun'

class SystemTest < Minitest::Test
  def setup
    @system = R80::System.new(0x10000, 0x0100)
  end

  def teardown
    # Do nothing
  end

  def test_exx
    #        ld   a,0x03
    #        ld   bc,0x0405
    #        ld   de,0x0607
    #        ld   hl,0x0809
    #        ld   ix,0x0a0b
    #        ld   iy,0x0c0d
    #        exx
    #        ld   a,0x00
    #        ld   bc,0xffee
    #        ld   de,0xddcc
    #        ld   hl,0xbbaa
    #        ret

    bytes = [0x3E, 0x03, 0x01, 0x05, 0x04, 0x11, 0x07, 0x06, 0x21, 0x09, 0x08,
             0xDD, 0x21, 0x0B, 0x0A, 0xFD, 0x21, 0x0D, 0x0C, 0xD9, 0x3E, 0x00,
             0x01, 0xEE, 0xFF, 0x11, 0xCC, 0xDD, 0x21, 0xAA, 0xBB, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=00 B=FFEE D=DDCC H=BBAA S=F802 P=F301  RET
    # 00 ------ '=00 '=0405 '=0607 '=0809 X=0A0B Y=0C0D
    assert_equal(12, steps, 'Bad step count')
    assert_equal(0x00, @system.registers.a, 'Incorrect A register')
    assert_equal(0xFFEE, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0xDDCC, @system.registers.de, 'Incorrect DE register')
    assert_equal(0xBBAA, @system.registers.hl, 'Incorrect HL register')
    assert_equal(0x00, @system.registers.alternate.a, 'Incorrect shadow A register')
    assert_equal(0x0405, @system.registers.alternate.bc, 'Incorrect shadow BC register')
    assert_equal(0x0607, @system.registers.alternate.de, 'Incorrect shadow DE register')
    assert_equal(0x0809, @system.registers.alternate.hl, 'Incorrect shadow HL register')
    assert_equal(0x0A0B, @system.registers.ix, 'Incorrect IX register')
    assert_equal(0x0C0D, @system.registers.iy, 'Incorrect IY register')
  end

  def test_inc_r
    #        ld   bc,0
    #        push bc
    #        pop  af
    #        ld   d,3
    #        inc  d
    #        push af
    #        pop  bc
    #        ld   d,0xff
    #        inc  d
    #        ret

    bytes = [0x01, 0x00, 0x00, 0xC5, 0xF1, 0x16, 0x03, 0x14, 0xF5, 0xC1, 0x16,
             0xFF, 0x14, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 50 ---FZ- A=00 B=0000 D=00FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(10, steps, 'Bad step count')
    assert_equal(0x50, @system.registers.f, 'Incorrect F register')
    assert_equal(0x00, @system.registers.d, 'Incorrect D register')
    assert_equal(0x0000, @system.registers.bc, 'Incorrect BC register')
  end

  def test_dec_r_1
    #        ld   d,3
    #        dec  d
    #        ret

    bytes = [0x16, 0x03, 0x15, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 03 CS---- A=FF B=00FF D=02FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(3, steps, 'Bad step count')
    assert_equal(0x03, @system.registers.f, 'Incorrect F register')
    assert_equal(0x02, @system.registers.d, 'Incorrect D register')
  end

  def test_dec_r_2
    #        ld   d,1
    #        dec  d
    #        ret

    bytes = [0x16, 0x01, 0x15, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 43 CS--Z- A=FF B=00FF D=00FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(3, steps, 'Bad step count')
    assert_equal(0x43, @system.registers.f, 'Incorrect F register')
    assert_equal(0x00, @system.registers.d, 'Incorrect D register')
  end

  def test_dec_r_3
    #        ld   d,0
    #        dec  d
    #        ret

    bytes = [0x16, 0x00, 0x15, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # BB CS-F-M A=FF B=00FF D=FFFF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(3, steps, 'Bad step count')
    assert_equal(0xBB, @system.registers.f, 'Incorrect F register')
    assert_equal(0xFF, @system.registers.d, 'Incorrect D register')
  end

  def test_ld_r_r_1
    #        ld   a,0x12
    #        ld   hl,data
    #        ld   (hl),a
    #        ld   a,0x01
    #        ld   b,a
    #        ld   ix,0x3344
    #        ld   h,ixl
    #        ld   iy,0x5566
    #        ld   l,iyh
    #        ld   ix,data
    #        ld   iy,data
    #        ld   e,(ix+0)
    #        ld   (iy+1),e
    #        ret
    # data:  db   0x03,0x00

    bytes = [0x3E, 0x12, 0x21, 0x24, 0x01, 0x77, 0x3E, 0x01, 0x47, 0xDD, 0x21,
             0x44, 0x33, 0xDD, 0x65, 0xFD, 0x21, 0x66, 0x55, 0xFD, 0x6C, 0xDD,
             0x21, 0x24, 0x01, 0xFD, 0x21, 0x24, 0x01, 0xDD, 0x5E, 0x00, 0xFD,
             0x73, 0x01, 0xC9, 0x03, 0x00]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=01 B=01FF D=0312 H=0124 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0124 Y=0124
    assert_equal(14, steps, 'Bad step count')
    assert_equal(0x01, @system.registers.b, 'Incorrect B register')
    assert_equal(0x12, @system.registers.e, 'Incorrect E register')
    assert_equal(0x01, @system.registers.h, 'Incorrect H register')
    assert_equal(0x24, @system.registers.l, 'Incorrect L register')
  end

  def test_ld_r_r_2
    #        ld   bc,0x1122
    #        ld   de,0x3344
    #        ld   ixh,c
    #        ld   ixl,b
    #        ld   iyh,e
    #        ld   iyl,d
    #        ld   e,ixh
    #        ld   d,ixl
    #        ld   c,iyh
    #        ld   b,iyl
    #        db   0xDD,0x7C ; ld   a,ixh
    #        db   0xFD,0x6F ; ld   iyl,a
    #        db   0xDD,0x7D ; ld   a,ixl
    #        db   0xFD,0x67 ; ld   iyh,a
    #        ret

    bytes = [0x01, 0x22, 0x11, 0x11, 0x44, 0x33, 0xDD, 0x61, 0xDD, 0x68, 0xFD,
             0x63, 0xFD, 0x6A, 0xDD, 0x5C, 0xDD, 0x55, 0xFD, 0x4C, 0xFD, 0x45,
             0xDD, 0x7C, 0xFD, 0x6F, 0xDD, 0x7D, 0xFD, 0x67, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=11 B=3344 D=1122 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=2211 Y=1122
    assert_equal(15, steps, 'Bad step count')
    assert_equal(0x11, @system.registers.a, 'Incorrect A register')
    assert_equal(0x3344, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x1122, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x2211, @system.registers.ix, 'Incorrect IX register')
    assert_equal(0x1122, @system.registers.iy, 'Incorrect IY register')
  end

  def test_m_ops
    #        ld   hl,data
    #        inc  (hl)
    #        ld   c,(hl)
    #        dec  (hl)
    #        ld   e,(hl)
    #        ld   (hl),0x3F
    #        ld   b,(hl)
    #        ret
    # data:  db   0x89

    bytes = [0x21, 0x0B, 0x01, 0x34, 0x4E, 0x35, 0x5E, 0x36, 0x3F, 0x46, 0xC9,
             0x89]

    steps = load_and_run bytes

    # Expected final state:
    # 8B CS---M A=FF B=3F8A D=0389 H=010B S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(8, steps, 'Bad step count')
    assert_equal(0x8B, @system.registers.f, 'Incorrect F register')
    assert_equal(0x3F8A, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x89, @system.registers.e, 'Incorrect E register')
  end

  def test_arith_8
    #        ld   a,0x0F
    #        ld   e,0x12
    #        xor  e
    #        push af
    #        pop  hl
    #        ld   a,0x18
    #        ld   b,0xFE
    #        ld   c,0x03
    #        add  a,b
    #        adc  a,c
    #        ld   c,0x05
    #        sub  c
    #        ld   c,0x01
    #        scf
    #        sbc  a,c
    #        ret

    bytes = [0x3E, 0x0F, 0x1E, 0x12, 0xAB, 0xF5, 0xE1, 0x3E, 0x18, 0x06, 0xFE,
             0x0E, 0x03, 0x80, 0x89, 0x0E, 0x05, 0x91, 0x0E, 0x01, 0x37, 0x99,
             0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 02 -S---- A=13 B=FE01 D=0312 H=1D0C S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(16, steps, 'Bad step count')
    assert_equal(0x02, @system.registers.f, 'Incorrect F register')
    assert_equal(0x13, @system.registers.a, 'Incorrect A register')
    assert_equal(0x1D0C, @system.registers.hl, 'Incorrect HL register')
  end

  def test_arith_16
    #        ld   hl,0x1000
    #        ld   bc,0xffff
    #        add  hl,bc
    #        ld   de,0xfffe
    #        add  hl,de
    #        ld   sp,0x8888
    #        add  hl,sp
    #        ret

    bytes = [0x21, 0x00, 0x10, 0x01, 0xFF, 0xFF, 0x09, 0x11, 0xFE, 0xFF, 0x19,
             0x31, 0x88, 0x88, 0x39, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # DC --EFZM A=FF B=FFFF D=FFFE H=9885 S=888A P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(8, steps, 'Bad step count')
    assert_equal(0x9885, @system.registers.hl, 'Incorrect HL register')
  end

  def test_daa
    #        ld   a,0x37
    #        scf
    #        daa
    #        push af
    #        pop  bc
    #        ld   a,0x37
    #        ccf
    #        daa
    #        push af
    #        pop  de
    #        sub  a
    #        ld   a,0x99
    #        daa
    #        ret

    bytes = [0x3E, 0x37, 0x37, 0x27, 0xF5, 0xC1, 0x3E, 0x37, 0x3F, 0x27, 0xF5,
             0xD1, 0x97, 0x3E, 0x99, 0x27, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 8E -SE--M A=99 B=9781 D=3D28 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(14, steps, 'Bad step count')
    assert_equal(0x99, @system.registers.a, 'Incorrect A register')
    assert_equal(0x8E, @system.registers.f, 'Incorrect F register')
    assert_equal(0x9781, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x3D28, @system.registers.de, 'Incorrect DE register')
  end

  def test_sub_r_1
    #        ld   bc,0xFD00
    #        ld   de,0xFC12
    #        ld   hl,0xFB13
    #        ld   ix,0x0102
    #        ld   iy,0x0304
    #        sub  a
    #        sub  b
    #        sub  c
    #        sub  d
    #        sub  e
    #        sub  h
    #        sub  l
    #        sub  ixh
    #        sub  ixl
    #        sub  iyh
    #        sub  iyl
    #        ret

    bytes = [0x01, 0x00, 0xFD, 0x11, 0x12, 0xFC, 0x21, 0x13, 0xFB, 0xDD, 0x21,
             0x02, 0x01, 0xFD, 0x21, 0x04, 0x03, 0x97, 0x90, 0x91, 0x92, 0x93,
             0x94, 0x95, 0xDD, 0x95, 0xDD, 0x94, 0xFD, 0x95, 0xFD, 0x94, 0xC9,
    ]

    steps = load_and_run bytes

    # Expected final state:
    # 9A -S-F-M A=DD B=FD00 D=FC12 H=FB13 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0102 Y=0304
    assert_equal(17, steps, 'Bad step count')
    assert_equal(0xDD, @system.registers.a, 'Incorrect A register')
    assert_equal(0x9A, @system.registers.f, 'Incorrect F register')
  end

  def test_sub_r_2
    #        ld   hl,data
    #        ld   ix,data
    #        ld   iy,data
    #        ld   a,0xff
    #        sub  (hl)
    #        sub  (ix+1)
    #        sub  (ix+2)
    #        ret
    # data:  db   0x17,0x18,0x19

    bytes = [0x21, 0x15, 0x01, 0xDD, 0x21, 0x15, 0x01, 0xFD, 0x21, 0x15, 0x01,
             0x3E, 0xFF, 0x96, 0xDD, 0x96, 0x01, 0xDD, 0x96, 0x02, 0xC9, 0x17,
             0x18, 0x19]

    steps = load_and_run bytes

    # Expected final state:
    # B2 -S-F-M A=B7 B=00FF D=03FF H=0115 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0115 Y=0115
    assert_equal(8, steps, 'Bad step count')
    assert_equal(0xB7, @system.registers.a, 'Incorrect A register')
    assert_equal(0xB2, @system.registers.f, 'Incorrect F register')
  end

  def test_stack
    #        ld   bc,0xFEDC
    #        push bc
    #        inc  bc
    #        push bc
    #        pop  de
    #        pop  hl
    #        dec  hl
    #        push hl
    #        pop  af
    #        ret

    bytes = [0x01, 0xDC, 0xFE, 0xC5, 0x03, 0xC5, 0xD1, 0xE1, 0x2B, 0xE5, 0xF1,
             0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # DB CS-FZM A=FE B=FEDD D=FEDD H=FEDB S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(10, steps, 'Bad step count')
    assert_equal(0xDB, @system.registers.f, 'Incorrect F register')
    assert_equal(0xFE, @system.registers.a, 'Incorrect A register')
    assert_equal(0xFEDD, @system.registers.de, 'Incorrect DE register')
    assert_equal(0xFEDB, @system.registers.hl, 'Incorrect HL register')
  end

  def test_aluixd
    #        ld   iy,data
    #        inc  (iy+2)
    #        ld   b,(iy+2)
    #        ld   a,0xA0
    #        add  a,(iy+3)
    #        sub  a,(iy+2)
    #        ret
    # data:  db   0x00, 0x01, 0x02, 0x03

    bytes = [0xFD, 0x21, 0x13, 0x01, 0xFD, 0x34, 0x02, 0xFD, 0x46, 0x02, 0x3E,
             0xA0, 0xFD, 0x86, 0x03, 0xFD, 0x96, 0x02, 0xC9, 0x00, 0x01, 0x02,
             0x03]

    steps = load_and_run bytes

    # Expected final state:
    # A2 -S---M A=A0 B=03FF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0113
    assert_equal(7, steps, 'Bad step count')
    assert_equal(0xA2, @system.registers.f, 'Incorrect F register')
    assert_equal(0xA0, @system.registers.a, 'Incorrect A register')
    assert_equal(0x03, @system.registers.b, 'Incorrect B register')
  end

  def test_bitixd
    #        ld   ix,data
    #        bit  1,(ix+2)
    #        push af
    #        pop  bc
    #        bit  2,(ix+2)
    #        push af
    #        pop  de
    #        ret
    # data:  db   0x00, 0x01, 0x02, 0x03

    bytes = [0xDD, 0x21, 0x11, 0x01, 0xDD, 0xCB, 0x02, 0x4E, 0xF5, 0xC1, 0xDD,
             0xCB, 0x02, 0x56, 0xF5, 0xD1, 0xC9, 0x00, 0x01, 0x02, 0x03]

    steps = load_and_run bytes

    # Expected final state:
    # 55 C-EFZ- A=FF B=FF11 D=FF55 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0111 Y=0000
    assert_equal(8, steps, 'Bad step count')
    assert_equal(0xFF11, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0xFF55, @system.registers.de, 'Incorrect DE register')
  end

  def test_incdecixd
    #        ld   ix,data
    #        inc  (ix+2)
    #        ld   b,(ix+2)
    #        dec  (ix+2)
    #        ld   c,(ix+2)
    #        push af
    #        ld   iy,data
    #        inc  (iy+3)
    #        ld   d,(iy+3)
    #        dec  (iy+3)
    #        ld   e,(iy+3)
    #        pop hl
    #        ret
    # data:  db   0x00, 0x01, 0x02, 0x03

    bytes = [0xDD, 0x21, 0x23, 0x01, 0xDD, 0x34, 0x02, 0xDD, 0x46, 0x02, 0xDD,
             0x35, 0x02, 0xDD, 0x4E, 0x02, 0xF5, 0xFD, 0x21, 0x23, 0x01, 0xFD,
             0x34, 0x03, 0xFD, 0x56, 0x03, 0xFD, 0x35, 0x03, 0xFD, 0x5E, 0x03,
             0xE1, 0xC9, 0x00, 0x01, 0x02, 0x03]

    steps = load_and_run bytes

    # Expected final state:
    # 03 CS---- A=FF B=0302 D=0403 H=FF03 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0123 Y=0123
    assert_equal(13, steps, 'Bad step count')
    assert_equal(0x03, @system.registers.f, 'Incorrect F register')
    assert_equal(0x0302, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x0403, @system.registers.de, 'Incorrect DE register')
    assert_equal(0xFF03, @system.registers.hl, 'Incorrect HL register')
  end

  def test_incdecixyhl
    #        ld   iy,0xFFFF
    #        db   0xFD,0x24 ; inc  iyh
    #        push af
    #        db   0xFD,0x25 ; dec  iyh
    #        push af
    #        db   0xFD,0x2C ; inc  iyl
    #        push af
    #        db   0xFD,0x2D ; dec  iyl
    #        push af
    #        pop  bc
    #        pop  de
    #        pop  hl
    #        pop  ix
    #        ret

    bytes = [0xFD, 0x21, 0xFF, 0xFF, 0xFD, 0x24, 0xF5, 0xFD, 0x25, 0xF5, 0xFD,
             0x2C, 0xF5, 0xFD, 0x2D, 0xF5, 0xC1, 0xD1, 0xE1, 0xDD, 0xE1, 0xC9,
    ]

    steps = load_and_run bytes

    # Expected final state:
    # BB CS-F-M A=FF B=FFBB D=FF51 H=FFBB S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=FF51 Y=FFFF
    assert_equal(14, steps, 'Bad step count')
    assert_equal(0xFF, @system.registers.a, 'Incorrect A register')
    assert_equal(0xBB, @system.registers.f, 'Incorrect F register')
    assert_equal(0xFFBB, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0xFF51, @system.registers.de, 'Incorrect DE register')
    assert_equal(0xFFBB, @system.registers.hl, 'Incorrect HL register')
    assert_equal(0xFF51, @system.registers.ix, 'Incorrect IX register')
  end

  def test_ldixiy
    #        ld   ix,(data1+00)
    #        ld   iy,(data1+02)
    #        ld   (data2+00),ix
    #        ld   (data2+03),iy
    #        ld   hl,data2
    #        ld   b,(hl)
    #        inc  hl
    #        ld   c,(hl)
    #        inc  hl
    #        ld   d,(hl)
    #        inc  hl
    #        ld   e,(hl)
    #        ret
    # data1: db   0xB1,0xB2,0xC1,0xC2
    # data2: db   0x00,0x00,0x00,0x00

    bytes = [0xDD, 0x2A, 0x1B, 0x01, 0xFD, 0x2A, 0x1D, 0x01, 0xDD, 0x22, 0x1F,
             0x01, 0xFD, 0x22, 0x22, 0x01, 0x21, 0x1F, 0x01, 0x46, 0x23, 0x4E,
             0x23, 0x56, 0x23, 0x5E, 0xC9, 0xB1, 0xB2, 0xC1, 0xC2, 0x00, 0x00,
             0x00, 0x00]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=FF B=B1B2 D=00C1 H=0122 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=B2B1 Y=C2C1
    assert_equal(13, steps, 'Bad step count')
    assert_equal(0xB2B1, @system.registers.ix, 'Incorrect IX register')
    assert_equal(0xC2C1, @system.registers.iy, 'Incorrect IY register')
    assert_equal(0xB1B2, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x00C1, @system.registers.de, 'Incorrect DE register')
  end

  def test_ldixiydn
    #        ld   ix,data
    #        ld   (ix+2),0xCA
    #        ld   b,(ix+2)
    #        ret
    # data:  db   0x00,0x00,0x00

    bytes = [0xDD, 0x21, 0x0C, 0x01, 0xDD, 0x36, 0x02, 0xCA, 0xDD, 0x46, 0x02,
             0xC9, 0x00, 0x00, 0x00]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=FF B=CAFF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=010C Y=0000
    assert_equal(4, steps, 'Bad step count')
    assert_equal(0xCA, @system.registers.b, 'Incorrect B register')
  end

  def test_ldixyhln
    #        ld   ixh,0x12
    #        ld   ixl,0x34
    #        ld   iyh,0x56
    #        ld   iyl,0x78
    #        ret

    bytes = [0xDD, 0x26, 0x12, 0xDD, 0x2E, 0x34, 0xFD, 0x26, 0x56, 0xFD, 0x2E,
             0x78, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=FF B=00FF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=1234 Y=5678
    assert_equal(5, steps, 'Bad step count')
    assert_equal(0x1234, @system.registers.ix, 'Incorrect IX register')
    assert_equal(0x5678, @system.registers.iy, 'Incorrect IY register')
  end

  def test_setresixd
    #        ld   ix,data
    #        set  7,(ix+1)
    #        res  1,(ix+1)
    #        ld   a,(ix+1)
    #        ret
    # data:  db   0x00,0x0F

    bytes = [0xDD, 0x21, 0x10, 0x01, 0xDD, 0xCB, 0x01, 0xFE, 0xDD, 0xCB, 0x01,
             0x8E, 0xDD, 0x7E, 0x01, 0xC9, 0x00, 0x0F]

    steps = load_and_run bytes

    # Expected final state:
    # FF CSEFZM A=8D B=00FF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0110 Y=0000
    assert_equal(5, steps, 'Bad step count')
    assert_equal(0x8D, @system.registers.a, 'Incorrect A register')
  end

  def test_jpcc
    #        ld   a,0x00
    #        ld   b,0x00
    #        inc  b
    #        jp   z,lab1
    #        or   0x01
    # lab1:  or   0x02
    #        dec  b
    #        jp   nc,lab2
    #        or   0x04
    # lab2:  or   0x08
    #        and  a
    #        jp   po,lab3
    #        or   0x10
    # lab3:  or   0x20
    #        inc  b
    #        jp   p,lab4
    #        or   0x40
    # lab4:  or   0x80
    #        ld   d,a
    #        ld   a,0x00
    #        ld   b,0x00
    #        inc  b
    #        jp   nz,lab5
    #        or   0x01
    # lab5:  or   0x02
    #        dec  b
    #        jp   c,lab6
    #        or   0x04
    # lab6:  or   0x08
    #        and  a
    #        jp   pe,lab7
    #        or   0x10
    # lab7:  or   0x20
    #        inc  b
    #        jp   m,lab8
    #        or   0x40
    # lab8:  or   0x80
    #        ret

    bytes = [0x3E, 0x00, 0x06, 0x00, 0x04, 0xCA, 0x0A, 0x01, 0xF6, 0x01, 0xF6,
             0x02, 0x05, 0xD2, 0x12, 0x01, 0xF6, 0x04, 0xF6, 0x08, 0xA7, 0xE2,
             0x1A, 0x01, 0xF6, 0x10, 0xF6, 0x20, 0x04, 0xF2, 0x22, 0x01, 0xF6,
             0x40, 0xF6, 0x80, 0x57, 0x3E, 0x00, 0x06, 0x00, 0x04, 0xC2, 0x2F,
             0x01, 0xF6, 0x01, 0xF6, 0x02, 0x05, 0xDA, 0x37, 0x01, 0xF6, 0x04,
             0xF6, 0x08, 0xA7, 0xEA, 0x3F, 0x01, 0xF6, 0x10, 0xF6, 0x20, 0x04,
             0xFA, 0x47, 0x01, 0xF6, 0x40, 0xF6, 0x80, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # A8 -----M A=FE B=01FF D=ABFF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(34, steps, 'Bad step count')
    assert_equal(0xFE, @system.registers.a, 'Incorrect A register')
    assert_equal(0xAB, @system.registers.d, 'Incorrect D register')
  end

  def test_jrcc
    #        ld   a,0x00
    #        ld   b,0x00
    #        inc  b
    #        jr   z,lab1
    #        or   0x01
    # lab1:  dec  b
    #        jr   nz,lab2
    #        or   0x02
    # lab2:  scf
    #        jr   nc,lab3
    #        or   0x04
    # lab3:  or   a
    #        jr   c,lab4
    #        or   0x08
    # lab4:  ret

    bytes = [0x3E, 0x00, 0x06, 0x00, 0x04, 0x28, 0x02, 0xF6, 0x01, 0x05, 0x20,
             0x02, 0xF6, 0x02, 0x37, 0x30, 0x02, 0xF6, 0x04, 0xB7, 0x38, 0x02,
             0xF6, 0x08, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 0C --E--- A=0F B=00FF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(15, steps, 'Bad step count')
    assert_equal(0x0C, @system.registers.f, 'Incorrect F register')
    assert_equal(0x0F, @system.registers.a, 'Incorrect A register')
  end

  def test_djnz
    #        ld   a,0x00
    #        jr   lab1
    #        inc  a
    # lab1:  ld   b,0x03
    # loop:  inc  a
    #        djnz loop
    #        ret

    bytes = [0x3E, 0x00, 0x18, 0x01, 0x3C, 0x06, 0x03, 0x3C, 0x10, 0xFD, 0xC9,
    ]

    steps = load_and_run bytes

    # Expected final state:
    # 01 C----- A=03 B=00FF D=03FF H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(10, steps, 'Bad step count')
    assert_equal(0x01, @system.registers.f, 'Incorrect F register')
    assert_equal(0x03, @system.registers.a, 'Incorrect A register')
    assert_equal(0x00, @system.registers.b, 'Incorrect B register')
  end

  def test_cp
    #        ld   b,0x00
    #        ld   a,0x23
    #        cp   0x23
    #        push af
    #        pop  de
    #        ld   h,e
    #        cp   0x24
    #        push af
    #        pop  de
    #        ld   l,e
    #        cp   0x22
    #        push af
    #        pop  de
    #        ld   c,e
    #        cp   b
    #        push af
    #        pop  de
    #        ld   b,e
    #        ret

    bytes = [0x06, 0x00, 0x3E, 0x23, 0xFE, 0x23, 0xF5, 0xD1, 0x63, 0xFE, 0x24,
             0xF5, 0xD1, 0x6B, 0xFE, 0x22, 0xF5, 0xD1, 0x4B, 0xB8, 0xF5, 0xD1,
             0x43, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 02 -S---- A=23 B=0222 D=2302 H=62B3 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(19, steps, 'Bad step count')
    assert_equal(0x02, @system.registers.b, 'Incorrect B register')
    assert_equal(0x22, @system.registers.c, 'Incorrect C register')
    assert_equal(0x62, @system.registers.h, 'Incorrect H register')
    assert_equal(0xB3, @system.registers.l, 'Incorrect L register')
  end

  def test_rlrr
    #        ld   a,0x01
    #        rl   a
    #        ld   b,a
    #        ld   a,0x80
    #        rl   a
    #        push af
    #        pop  de
    #        rl   a
    #        ld   c,a
    #        exx
    #        ld   a,0x01
    #        rr   a
    #        push af
    #        pop  bc
    #        rr   a
    #        ld   d,a
    #        rr   a
    #        ld   e,a
    #        ret

    bytes = [0x3E, 0x01, 0xCB, 0x17, 0x47, 0x3E, 0x80, 0xCB, 0x17, 0xF5, 0xD1,
             0xCB, 0x17, 0x4F, 0xD9, 0x3E, 0x01, 0xCB, 0x1F, 0xF5, 0xC1, 0xCB,
             0x1F, 0x57, 0xCB, 0x1F, 0x5F, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 00 ------ A=40 B=0045 D=8040 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0301 '=0045 '=0000 X=0000 Y=0000
    assert_equal(19, steps, 'Bad step count')
    assert_equal(0x0045, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x8040, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x03, @system.registers.alternate.b, 'Incorrect shadow B register')
    assert_equal(0x0045, @system.registers.alternate.de, 'Incorrect shadow DE register')
  end

  def test_rlcrrc
    #        ld   a,0x01
    #        rlc  a
    #        ld   b,a
    #        ld   a,0x80
    #        rlc  a
    #        push af
    #        pop  de
    #        rl   a
    #        ld   c,a
    #        exx
    #        ld   a,0x01
    #        rrc  a
    #        push af
    #        pop  bc
    #        rrc  a
    #        ld   d,a
    #        rrc  a
    #        ld   e,a
    #        ret

    bytes = [0x3E, 0x01, 0xCB, 0x07, 0x47, 0x3E, 0x80, 0xCB, 0x07, 0xF5, 0xD1,
             0xCB, 0x17, 0x4F, 0xD9, 0x3E, 0x01, 0xCB, 0x0F, 0xF5, 0xC1, 0xCB,
             0x0F, 0x57, 0xCB, 0x0F, 0x5F, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 20 ------ A=20 B=8081 D=4020 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0203 '=0101 '=0000 X=0000 Y=0000
    assert_equal(19, steps, 'Bad step count')
    assert_equal(0x20, @system.registers.f, 'Incorrect F register')
    assert_equal(0x8081, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x4020, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x02, @system.registers.alternate.b, 'Incorrect shadow B register')
    assert_equal(0x0101, @system.registers.alternate.de, 'Incorrect shadow DE register')
  end

  def test_slasra
    #        ld   a,0x21
    #        sla  a
    #        ld   b,a
    #        ld   a,0x82
    #        sla  a
    #        push af
    #        pop  de
    #        sla  a
    #        ld   c,a
    #        exx
    #        ld   a,0x21
    #        sra  a
    #        push af
    #        pop  bc
    #        sra  a
    #        ld   d,a
    #        sra  a
    #        ld   e,a
    #        ret

    bytes = [0x3E, 0x21, 0xCB, 0x27, 0x47, 0x3E, 0x82, 0xCB, 0x27, 0xF5, 0xD1,
             0xCB, 0x27, 0x4F, 0xD9, 0x3E, 0x21, 0xCB, 0x2F, 0xF5, 0xC1, 0xCB,
             0x2F, 0x57, 0xCB, 0x2F, 0x5F, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 00 ------ A=04 B=1001 D=0804 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=4208 '=0401 '=0000 X=0000 Y=0000
    assert_equal(19, steps, 'Bad step count')
    assert_equal(0x1001, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x0804, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x42, @system.registers.alternate.b, 'Incorrect shadow B register')
    assert_equal(0x0401, @system.registers.alternate.de, 'Incorrect shadow DE register')
  end

  def test_sllsrl
    #        ld   a,0x21
    #        scf
    #        db   0xCB,0x37 ; sll  a
    #        ld   b,a
    #        ld   a,0x82
    #        db   0xCB,0x37 ; sll  a
    #        push af
    #        pop  de
    #        ccf
    #        sla  a
    #        ld   c,a
    #        exx
    #        ld   a,0x21
    #        srl  a
    #        push af
    #        pop  bc
    #        sra  a
    #        ld   d,a
    #        srl  a
    #        ld   e,a
    #        ret

    bytes = [0x3E, 0x21, 0x37, 0xCB, 0x37, 0x47, 0x3E, 0x82, 0xCB, 0x37, 0xF5,
             0xD1, 0x3F, 0xCB, 0x27, 0x4F, 0xD9, 0x3E, 0x21, 0xCB, 0x3F, 0xF5,
             0xC1, 0xCB, 0x2F, 0x57, 0xCB, 0x3F, 0x5F, 0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 00 ------ A=04 B=1001 D=0804 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=430A '=0505 '=0000 X=0000 Y=0000
    assert_equal(21, steps, 'Bad step count')
    assert_equal(0x1001, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x0804, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x43, @system.registers.alternate.b, 'Incorrect shadow B register')
    assert_equal(0x0505, @system.registers.alternate.de, 'Incorrect shadow DE register')
  end

  def test_retcc
    #        ld   a,0x00
    #        call labz
    #        call labnz
    #        ret
    # labz:  ld   e,0x00
    #        inc  e
    #        ret  z
    #        or   0x01
    #        ret
    # labnz: ld   e,0x00
    #        inc  e
    #        ret  nz
    #        or   0x02
    #        ret

    bytes = [0x3E, 0x00, 0xCD, 0x09, 0x01, 0xCD, 0x10, 0x01, 0xC9, 0x1E, 0x00,
             0x1C, 0xC8, 0xF6, 0x01, 0xC9, 0x1E, 0x00, 0x1C, 0xC0, 0xF6, 0x02,
             0xC9]

    steps = load_and_run bytes

    # Expected final state:
    # 00 ------ A=01 B=00FF D=0301 H=0000 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(12, steps, 'Bad step count')
    assert_equal(0x01, @system.registers.a, 'Incorrect A register')
  end

  def test_cpir_1
    #        ld   a,0x43
    #        ld   bc,0x03
    #        ld   hl,data
    #        cpir
    #        ret
    # data:  db   0x42,0x43,0x44

    bytes = [0x3E, 0x43, 0x01, 0x03, 0x00, 0x21, 0x0B, 0x01, 0xED, 0xB1, 0xC9,
             0x42, 0x43, 0x44]

    steps = load_and_run bytes

    # Expected final state:
    # 47 CSE-Z- A=43 B=0001 D=03FF H=010D S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(5, steps, 'Bad step count')
    assert_equal(0x43, @system.registers.a, 'Incorrect A register')
    assert_equal(0x47, @system.registers.f, 'Incorrect F register')
    assert_equal(0x0001, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x010D, @system.registers.hl, 'Incorrect HL register')
  end

  def test_cpir_2
    #        ld   a,0x99
    #        ld   bc,0x03
    #        ld   hl,data
    #        cpir
    #        ret
    # data:  db   0x42,0x43,0x44

    bytes = [0x3E, 0x99, 0x01, 0x03, 0x00, 0x21, 0x0B, 0x01, 0xED, 0xB1, 0xC9,
             0x42, 0x43, 0x44]

    steps = load_and_run bytes

    # Expected final state:
    # 03 CS---- A=99 B=0000 D=03FF H=010E S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(5, steps, 'Bad step count')
    assert_equal(0x99, @system.registers.a, 'Incorrect A register')
    assert_equal(0x03, @system.registers.f, 'Incorrect F register')
    assert_equal(0x0000, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x010E, @system.registers.hl, 'Incorrect HL register')
  end

  def test_cpdr_1
    #        ld   a,0x43
    #        ld   bc,0x03
    #        ld   hl,data+2
    #        cpdr
    #        ret
    # data:  db   0x42,0x43,0x44

    bytes = [0x3E, 0x43, 0x01, 0x03, 0x00, 0x21, 0x0D, 0x01, 0xED, 0xB9, 0xC9,
             0x42, 0x43, 0x44]

    steps = load_and_run bytes

    # Expected final state:
    # 47 CSE-Z- A=43 B=0001 D=03FF H=010B S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(5, steps, 'Bad step count')
    assert_equal(0x43, @system.registers.a, 'Incorrect A register')
    assert_equal(0x47, @system.registers.f, 'Incorrect F register')
    assert_equal(0x0001, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x010B, @system.registers.hl, 'Incorrect HL register')
  end

  def test_ldir_1
    #        ld   bc,0x02
    #        ld   hl,data1
    #        ld   de,data2
    #        ldir
    #        ld   a,(data2)
    #        ret
    # data1: db   0x42,0x43
    # data2: db   0x00,0x00

    bytes = [0x01, 0x02, 0x00, 0x21, 0x0F, 0x01, 0x11, 0x11, 0x01, 0xED, 0xB0,
             0x3A, 0x11, 0x01, 0xC9, 0x42, 0x43, 0x00, 0x00]

    steps = load_and_run bytes

    # Expected final state:
    # E1 C---ZM A=42 B=0000 D=0113 H=0111 S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(6, steps, 'Bad step count')
    assert_equal(0x42, @system.registers.a, 'Incorrect A register')
    assert_equal(0x0000, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x0113, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x0111, @system.registers.hl, 'Incorrect HL register')
  end

  def test_lddr_1
    #        ld   bc,0x02
    #        ld   hl,data1+1
    #        ld   de,data2+1
    #        lddr
    #        ld   a,(data2+1)
    #        ret
    # data1: db   0x42,0x43
    # data2: db   0x00,0x00

    bytes = [0x01, 0x02, 0x00, 0x21, 0x10, 0x01, 0x11, 0x12, 0x01, 0xED, 0xB8,
             0x3A, 0x12, 0x01, 0xC9, 0x42, 0x43, 0x00, 0x00]

    steps = load_and_run bytes

    # Expected final state:
    # C1 C---ZM A=43 B=0000 D=0110 H=010E S=F802 P=F301  RET
    # 00 ------ '=00 '=0000 '=0000 '=0000 X=0000 Y=0000
    assert_equal(6, steps, 'Bad step count')
    assert_equal(0x43, @system.registers.a, 'Incorrect A register')
    assert_equal(0x0000, @system.registers.bc, 'Incorrect BC register')
    assert_equal(0x0110, @system.registers.de, 'Incorrect DE register')
    assert_equal(0x010E, @system.registers.hl, 'Incorrect HL register')
  end

  private

  # Load a sequence of bytes into RAM at 0x0100, execute it, and return the number of steps
  def load_and_run(bytes)
    # Load a trivial program
    load_ram bytes

    # Run it to completion
    steps = 0
    while @system.running
      steps += 1
      @system.execute_instruction
    end

    steps
  end

  # Helper to load an array of bytes into RAM starting at 0x0100
  def load_ram(bytes)
    @system.memory[0x0100, bytes.size] = bytes.pack('c*')
  end
end
