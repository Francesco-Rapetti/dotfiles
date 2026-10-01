// Draws the icons of the audio items of SketchyBar for the devices whose speaker and microphone
// SF Symbols doesn't tell apart: the Mac (a laptop, or else a desktop), a display and audio glasses,
// each with a speaker badge, a microphone badge or both side by side at its bottom right, from the
// SF Symbols of the SF Pro font. A gap cut around the badges sets them apart, as in the SF Symbols
// badges. SketchyBar can't color images, so the color is baked in
// It also draws, without badges, the SF Symbols of the other devices, for the popup of audio.sh:
// its rows have the name after the icon and a text on the right, so the icon has to be an image
// Usage: osascript -l JavaScript audio_icons.js <output directory> <RRGGBB>
// which writes <device>_<badges>.png, e.g. laptop_speaker.png or glasses_speaker_microphone.png,
// and <symbol>.png, e.g. headphones.png

ObjC.import('AppKit')
ObjC.import('CoreText')

// The symbol of each device, how big its badges are compared with those of the Mac and how much of
// them sticks out of its right side: the glasses are much lower than the computers, and a badge on
// them would hide a lens
const DEVICES = {
  laptop: {glyph: '􀟛', badges: 1, out: 0},     // laptopcomputer
  desktop: {glyph: '􀙗', badges: 1, out: 0},    // desktopcomputer
  display: {glyph: '􀢹', badges: 1, out: 0},    // display
  glasses: {glyph: '􀖆', badges: 1, out: 0.6},    // eyeglasses
}
const BADGES = {speaker: '􀊧', microphone: '􀊱'}  // speaker.wave.2.fill, mic.fill
// Next to another badge the speaker loses its waves, which would run into it at the size of the bar
const PAIRED = {speaker: '􀊡'}                     // speaker.fill
const BADGE_SETS = [['speaker'], ['microphone'], ['speaker', 'microphone']]
// The symbols of audio.sh, by name
const SYMBOLS = {
  'speaker.wave.2': '􀊦',
  hifispeaker: '􀝎',
  headphones: '􀑈',
  headset: '􂣵',
  airpods: '􀟥',
  'airpods.pro': '􂭃',
  'airpods.max': '􀺹',
  eyeglasses: '􀖆',
  display: '􀢹',
  airplayaudio: '􀑢',
  waveform: '􀙫',
  mic: '􀊰',
  'music.mic': '􀑫',
}
// Points of the SF Pro of the audio icons (14), drawn at 4 px per point as audio.sh expects
const SIZE = 14, SCALE = 4
// The size of the badges, smaller when there are two so they don't cover the whole device, and
// the gap around them, in points. At the same size the SF Symbols look as big as each other: the
// microphone, thinner, is taller than the speaker
const BADGE = 9.8, BADGES_2 = 8, GAP = 1.2

// The glyph as a CoreText line, in the color of the context, and the bounds of its ink. JXA can't
// alloc an NSAttributedString nor use the CoreText constants, hence new and the names of the keys
function line(text, size) {
  const string = $.NSMutableAttributedString.new
  string.mutableString.appendString(text)
  const all = $.NSMakeRange(0, string.length)
  string.addAttributeValueRange('NSFont', $.NSFont.fontWithNameSize('SF Pro Semibold', size * SCALE), all)
  string.addAttributeValueRange('CTForegroundColorFromContext', $.NSNumber.numberWithBool(true), all)
  const line = $.CTLineCreateWithAttributedString(string)
  return {line, bounds: $.CTLineGetImageBounds(line, null)}
}

function icon(device, kinds, color, output) {
  const base = line(device.glyph, SIZE)
  const size = (kinds.length > 1 ? BADGES_2 : BADGE) * device.badges
  const badges = kinds.map(kind => line((kinds.length > 1 && PAIRED[kind]) || BADGES[kind], size))
  const c = base.bounds

  // The bottom right corner of the badges sticks out of the device's by a third of the gap, or by
  // that part of their width, and the icon grows upward if a badge is taller than the device
  const badgesWidth = badges.reduce((sum, badge) => sum + badge.bounds.size.width, 0) + GAP * SCALE * (badges.length - 1)
  const out = kinds.length ? GAP * SCALE / 3 : 0
  const width = Math.ceil(c.size.width + Math.max(out, badgesWidth * device.out))
  const height = Math.ceil(Math.max(c.size.height + out, ...badges.map(badge => badge.bounds.size.height)))
  // Where each line starts so that its ink lands there (the ink is offset from the line origin):
  // the badges from the right, the gap apart
  const baseAt = {x: -c.origin.x, y: out - c.origin.y}
  let right = width
  const badgesAt = badges.slice().reverse().map(badge => {
    const b = badge.bounds
    const at = {x: right - b.size.width - b.origin.x, y: -b.origin.y}
    right -= b.size.width + GAP * SCALE
    return at
  }).reverse()

  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))
  const context = $.NSGraphicsContext.currentContext.CGContext
  $.CGContextSetRGBFillColor(context, ...color, 1)
  $.CGContextSetRGBStrokeColor(context, ...color, 1)
  const draw = (text, at) => {
    $.CGContextSetTextPosition(context, at.x, at.y)
    $.CTLineDraw(text.line, context)
  }

  draw(base, baseAt)
  // The gap: the badges drawn thicker, erasing, before any of them is drawn
  $.CGContextSetBlendMode(context, $.kCGBlendModeClear)
  $.CGContextSetTextDrawingMode(context, $.kCGTextFillStroke)
  $.CGContextSetLineWidth(context, 2 * GAP * SCALE)
  $.CGContextSetLineJoin(context, $.kCGLineJoinRound)
  badges.forEach((badge, i) => draw(badge, badgesAt[i]))
  $.CGContextSetBlendMode(context, $.kCGBlendModeNormal)
  $.CGContextSetTextDrawingMode(context, $.kCGTextFill)
  badges.forEach((badge, i) => draw(badge, badgesAt[i]))
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}

function run(argv) {
  const [directory, hex] = argv
  const color = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null)
  for (const [name, device] of Object.entries(DEVICES)) {
    for (const kinds of BADGE_SETS) icon(device, kinds, color, `${directory}/${name}_${kinds.join('_')}.png`)
  }
  for (const [name, glyph] of Object.entries(SYMBOLS)) icon({glyph, badges: 1, out: 0}, [], color, `${directory}/${name}.png`)
}
