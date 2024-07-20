--[[  gp4.lua

GuitarPro v4 tab parser.

2024, Stanislav Mikhel ]]

local utils = require('src.utils')
local gp3 = require('src.gp3')


local gp4 = {}
-- inheritance
setmetatable(gp4, {__index = gp3})

gp4.readSong = function (self, s)
  local data = utils.data:init(s)
  local ver = data:bstring()
  self._version = string.sub(ver, 21, 24)
  -- expected 30 byte intro
  if data.pos < 32 then data.pos = 32 end
  local song = {}
  if string.find(ver, '^CLIPBOARD') then
    self._version = string.sub(ver, 14, 17) .. '0'
    song.clipboard = self:readClipboard()
  end
  song.info    = self:readInfo(data)
  song.triplet = data:bool()
  song.lyrics  = self:readLyrics(data)
  song.tempo   = data:int()
  song.key     = data:int()
  data:skip(1)
  song.midi    = self:readMidiChannels(data)
  local measures = data:int(data)
  local tracks   = data:int(data)
  song.measureHeaders = {}
  for i = 1, measures do
    song.measureHeaders[i] = self:readMeasureHeader(data)
  end
  song.tracks = {}
  for i = 1, tracks do
    song.tracks[i] = self:readTrack(data)
  end
  song.measures = {}
  for i = 1, measures do
    song.measures[i] = self:readMeasure(data)
  end
  return song
end

gp4.readClipboard = function (self, data)
  local cb = {}
  cb.startMeasure = data:int()
  cb.stopMeasure  = data:int()
  cb.startTrack   = data:int()
  cb.stopTrack    = data:int()
  return cb
end

gp4.readLyrics = function (self, data)
  local lines = {}
  lines.track = data:int()
  for i = 1, 5 do
    local line = {}
    line.startingMeasure = data:int()
    line.lyrics          = data:istring()
    lines[i] = line
  end
  return lines
end

gp4.readNewChord = function (self, data)
  local chord = {new=true}
  chord.sharp = data:bool()
  data:skip(3)
  chord.root  = data:byte()
  chord.type  = data:byte()
  chord.extention = data:byte()
  chord.bass  = data:int()
  chord.tonality = data:int()
  chord.add   = data:bool()
  local prev = data.pos
  chord.name  = data:bstring()
  data.pos = prev + 23  -- 22 bytes length
  chord.alt5  = data:byte()
  chord.alt9  = data:byte()
  chord.alt11 = data:byte()
  chord.first = data:int()
  local str = {}
  for i = 1, 7 do
    str[i] = data:int()
  end
  chord.string = str
  -- barre
  local bar = {frets={}, start={}, ends={}}
  bar.len = data:byte()
  for i = 1, 5 do
    bar.frets[i] = data:byte()
  end
  for i = 1, 5 do
    bar.start[i] = data:byte()
  end
  for i = 1, 5 do
    bar.ends[i]  = data:byte()
  end
  -- rest
  chord.omission = {}
  for i = 1, 7 do
    chord.omission[i] = data:bool()
  end
  data:skip(1)
  local fingers = {}
  for i = 1, 7 do
    fingers[i] = data:sbyte()
  end
  chord.fingers = fingers
  chord.show = data:bool()
  return chord
end

gp4.readBeatEffects = function (self, data)
  local flags1 = data:byte()
  local flags2 = data:byte()
  local effects = {flags1=flags1, flags2=flags2}
  if flags1 & 0x02 ~= 0 then effects.vibrato = true end
  if flags1 & 0x10 ~= 0 then effects.fadeIn  = true end
  if flags1 & 0x20 ~= 0 then 
    effects.slap       = data:sbyte() 
  end
  if flags2 & 0x04 ~= 0 then 
    effects.tremoloBar = self:readTremoloBar(data) 
  end
  if flags1 & 0x40 ~= 0 then
    local up   = data:sbyte()
    local down = data:sbyte()
    effects.beatStroke = {up, down}
  end
  if flags2 & 0x01 ~= 0 then effects.hasRasgeuado = true end
  if flags2 & 0x02 ~= 0 then 
    effects.pickStroke = data:sbyte() 
  end
  return effects
end

gp4.readTremoloBar = function (self, data) return self:readBend(data) end

gp4.readMixTable = function (self, data)
  local tbl = gp3.readMixTable(self, data)
  return self:readMixTableFlags(data, tbl)
end

gp4.readMixTableFlags = function (self, data, t)
  local flags = data:sbyte()
  if t.volume  and flags & 0x01 ~= 0 then t.volumeAll = true end
  if t.balance and flags & 0x02 ~= 0 then t.balanceAll = true end
  if t.chorus  and flags & 0x04 ~= 0 then t.chorusAll = true end
  if t.reverb  and flags & 0x08 ~= 0 then t.reverbAll = true end
  if t.phaser  and flags & 0x10 ~= 0 then t.phaserAll = true end
  if t.tremolo and flags & 0x20 ~= 0 then t.tremoloAll = true end
  t.flags = flags
  return t
end

gp4.readNoteEffect = function (self, data)
  local effects = {}
  local flags1 = data:sbyte()
  local flags2 = data:sbyte()
  if flags1 & 0x02 ~= 0 then effects.hammer = true end
  if flags1 & 0x08 ~= 0 then effects.letRing = true end
  if flags2 & 0x01 ~= 0 then effects.stoccato = true end
  if flags2 & 0x02 ~= 0 then effects.palmMute = true end
  if flags2 & 0x04 ~= 0 then effects.vibrato = true end
  if flags1 & 0x01 ~= 0 then effects.bend  = self:readBend(data) end
  if flags1 & 0x10 ~= 0 then effects.grace = self:readGrace(data) end
  if flags2 & 0x04 ~= 0 then effects.tremoloPicking = data:sbyte() end
  if flags2 & 0x08 ~= 0 then effects.slide = self:readSlides(data) end
  if flags2 & 0x10 ~= 0 then effects.harmonic = self:readHarmonic(data) end
  if flags2 & 0x20 ~= 0 then effects.trill    = self:readTrill(data) end
  return effects
end

gp4.readTrill = function (self, data)
  local trill = {}
  trill.fret     = data:sbyte()
  trill.duration = data:sbyte()
  return trill
end

gp4.readSlides = function (self, data)
  return {data:sbyte()}
end

gp4.readHarmonic = function (self, data)
  return {type = data:sbyte()}
end

return gp4


--local bin = utils.read(arg[1])
--gp4:readSong(bin)