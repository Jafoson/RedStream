import 'dart:ffi';

bool isArm32() => Abi.current() == Abi.androidArm;
