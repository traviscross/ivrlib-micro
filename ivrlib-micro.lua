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

function appc(app,...)
  local ss=table.join({...}," ")
  return session:execute(app,ss)
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

function log(level,msg)
  local i=debug.getinfo(2,"nlS")
  local src=(i and i.short_src) or "stdin"
  local line=(i and i.currentline) or 0
  local name=(i and i.name) or "<none>"
  if session and session.consoleLog2 then
    return session:consoleLog2(level,src,name,line,msg.."\n")
  elseif session and session.consoleLog then
    return session:consoleLog(level,msg.."\n")
  elseif freeswitch and freeswitch.consoleLog2 then
    return freeswitch.consoleLog2(level,src,name,line,msg.."\n")
  elseif freeswitch and freeswitch.consoleLog then
    return freeswitch.consoleLog(level,msg.."\n")
  else
    return print("["..string.upper(level).."] "..src..":"..line.." "..msg)
  end
end

function ready() return session:ready() end
local sappend
function sappend(s1,s2) if s1 and #s1>0 then return s1..s2 else return s2 end end
function getvar_a(k) return session:getVariable(k) end
function setvar_a(k,v) if v then return session:setVariable(k,v) end end
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
  if not x or x:match("^-ERR") then return nil
  else return x end
end

function add_ivr_dispatcher2(xs,entry,dispatcher)
  entry.dp=dispatcher
  table.insert(xs,entry)
end

function add_ivr_dispatcher(xs,entry,dispatcher)
  local f=function(k,...) return dispatcher(...) end
  return add_ivr_dispatcher2(xs,entry,f)
end

local ivr_dispatch_entry_comp
function ivr_dispatch_entry_comp(x,y)
  if (x.prio or 0) == (y.prio or 0) then
    if y.str then return false
    elseif x.str then return true
    elseif y.regex then return false
    elseif x.regex then return true
    elseif y.fn then return false
    elseif x.fn then return true
    else return false end
  elseif (x.prio or 0) < (y.prio or 0) then
    return true
  else return false end
end

function ivr_dispatch_map(xs)
  local dmap={} i=1 last_prio=nil
  table.sort(xs,ivr_dispatch_entry_comp)
  for _,v in pairs(xs) do
    if (last_prio and (v.prio or 0) > last_prio) or not last_prio then
      if last_prio then i=i+1 end
      last_prio=(v.prio or 0)
      dmap[i]={strm={},regexm={},fnm={},dpm={}}
    end
    if v.str then dmap[i].strm[v.str]=v
    elseif v.regex then dmap[i].regexm[v.regex]=v
    elseif v.fn then dmap[i].fnm[v.fn]=v
    else dmap[i].dpm[v.dp]=v end
  end
  return dmap
end

local ivr_dispatch_match
function ivr_dispatch_match(x,v)
  local xs=nil
  if x.str then
    if x.str ~= v then return false end
    xs={v}
  end
  if x.regex then
    xs={string.match(v,x.regex)}
    if #xs==0 then return false end
  end
  if x.fn then
    xs={x.fn(x,v)}
    if #xs==0 then return false end
  end
  return xs
end

local from_ivr_entry
function from_ivr_entry(x)
  local s="{"
  s=s.."prio="..(x.prio or 0)
  if x.str then s=s..",str="..x.str end
  if x.regex then s=s..",regex="..x.regex end
  s=s.."}"
  return s
end

function ivr_dispatch(dseq,v)
  log("debug","IVR dispatch looking for match for "..v)
  local dmap=ivr_dispatch_map(dseq)
  for p,m in pairs(dmap) do
    local x=m.strm[v]
    if x then
      local xs=ivr_dispatch_match(x,v)
      if xs then
        log("debug","IVR dispatch matched by string `"..v.."`")
        return true,x.dp(x,table.unpack(xs)) end
    end
    for _,x in pairs(m.regexm) do
      log("debug","Testing `"..v.."` against IVR entry "..from_ivr_entry(x))
      if string.match(v,x.regex) then
        local xs=ivr_dispatch_match(x,v)
        if xs then
          log("debug","IVR dispatch matched by regex; `"..v.."`")
          return true,x.dp(x,table.unpack(xs)) end
      end
    end
    for _,x in pairs(m.fnm) do
      if x.fn(x,v) then
        local xs=ivr_dispatch_match(x,v)
        if xs then
          log("debug","IVR dispatch matched by function; `"..v.."`")
          return true,x.dp(x,table.unpack(xs)) end
      end
    end
    for _,x in pairs(m.dpm) do
      local xs={x.dp(x,v)}
      if xs[1] ~= false then
        log("debug","IVR dispatch matched by dispatcher; `"..v.."`")
        return true,table.unpack(xs) end
    end
  end
  return nil
end
