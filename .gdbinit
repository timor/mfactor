define reset
  load
  set $sp=*0
  set $pc=*4
end

tar rem :1234
reset
