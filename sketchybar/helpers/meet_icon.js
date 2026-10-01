// Draws the Google Meet logo that the popup of calendar.sh shows next to the events with a Meet
// link: the one of MeetingBar, a vector in its asset catalog. The logo is Google's, so it isn't in
// the repo: without MeetingBar it is the video.fill SF Symbol, in the given color since SketchyBar
// can't color images
// Usage: osascript -l JavaScript meet_icon.js <output png> <RRGGBB>
// which writes a square of SIZE points at 4 px per point, as calendar.sh expects

ObjC.import('AppKit')

const MEETINGBAR = '/Applications/MeetingBar.app'
const SIZE = 16, SCALE = 4
// The camera, as tall as the logo, which fills the width of its square
const SYMBOL_SIZE = 12

function run(argv) {
  const [output, hex] = argv
  const pixels = SIZE * SCALE
  const rect = $.NSMakeRect(0, 0, pixels, pixels)
  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, pixels, pixels, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))

  const bundle = $.NSBundle.bundleWithPath(MEETINGBAR)
  const logo = bundle.isNil() ? $() : bundle.imageForResource('google_meet_icon')
  if (!logo.isNil()) {
    logo.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
  } else {
    const configuration = $.NSImageSymbolConfiguration.configurationWithPointSizeWeight(SYMBOL_SIZE * SCALE, $.NSFontWeightSemibold)
    const symbol = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription('video.fill', $())
      .imageWithSymbolConfiguration(configuration)
    const size = symbol.size
    symbol.drawInRectFromRectOperationFraction(
      $.NSMakeRect((pixels - size.width) / 2, (pixels - size.height) / 2, size.width, size.height),
      $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
    // Source atop paints only where the symbol is, as in claude_icon.js
    const [red, green, blue] = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)
    $.NSColor.colorWithSRGBRedGreenBlueAlpha(red, green, blue, 1).set
    $.NSRectFillUsingOperation(rect, $.NSCompositingOperationSourceAtop)
  }
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}
