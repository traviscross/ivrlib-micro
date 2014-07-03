-- Copyright (c) 2014 Travis Cross <tc@traviscross.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

-- This library implements some commonly-needed routines for
-- FreeSWITCH IVRs and Lua dialplans.

local api
if freeswitch then
  api=freeswitch.API()
  if not ACTIONS then
    ACTIONS={}
  end
end

function table.join(table,sep)
  local acc=""
  for _,v in pairs(table) do
    if acc=="" then
      acc=v
    else
      acc=acc..sep..v
    end
  end
  return acc
end

function appq(app,...)
  local ss=table.join({...}," ")
  return table.insert(ACTIONS,{app,ss})
end

function apic(cmd,...)
  local ss=table.join({...}," ")
  return api:execute(cmd,ss)
end

function getvar(var,uuid)
  if uuid then return apic("uuid_getvar",uuid,var) end
  if session then return session:getVariable(var) end
  return apic("global_getvar",var)
end
function getvarp(var) return getvar(var)=="true" end

function setvar(var,val,uuid)
  if uuid then return apic("uuid_setvar",uuid,var,val) end
  if session then return session:setVariable(var,val) end
  return apic("global_setvar",var.."="..val)
end

function log(level,msg) return freeswitch.consoleLog(level,msg.."\n") end

function ready() return session:ready() end
local sappend
function sappend(s1,s2) if s1 and #s1>0 then return s1..s2 else return s2 end end
function getvar_a(k) return session:getVariable(k) end
function setvar_a(k,v) return session:setVariable(k,v) end
local append_var
function append_var(k,v) return setvar_a(k,sappend(session:getVariable(k),v)) end
function export(k) return append_var("export_vars",","..k) end
function setvar_ab(k,v) if v then setvar_a(k,v) end return export(k) end
function setvar_b(k,v) return setvar_ab("nolocal:"..k,v) end
function cpvar(dst,src,uuid)
  if not src then src=dst end
  return setvar(dst,getvar(src,uuid),uuid)
end
function cpvar_aa(dst,src)
  if not src then src=dst end
  return setvar_a(dst,getvar_a(src))
end
function cpvar_ab(dst,src)
  if not src then src=dst end
  return setvar_b(dst,getvar_a(src))
end

local urlencode_char
function urlencode_char(s,i)
  return "%"..string.format("%02x",string.byte(string.sub(s,i,i)))
end

function urlencode(s)
  local r=""
  for i=1, #s do
    r=r..urlencode_char(s,i)
  end
  return r
end

function nerr(x)
  if x:match("^-ERR") then return nil
  else return x end
end
