package main

deny contains msg if {
  input.kind == "Pod"
  input.spec.hostNetwork == true
  msg := "hostNetwork must not be true"
}
