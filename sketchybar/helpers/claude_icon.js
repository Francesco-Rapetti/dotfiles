// Tints the Claude spark of the Claude app's menu bar icon, for the claude item of SketchyBar,
// which can't color an image. The icon is white on transparent, so the color replaces its white
// Usage: osascript -l JavaScript claude_icon.js <input png> <output png> <RRGGBB>

ObjC.import('AppKit')

function run(argv) {
  const [input, output, hex] = argv
  const source = $.NSImage.alloc.initWithContentsOfFile(input)
  const pixels = source.representations.objectAtIndex(0)
  const width = pixels.pixelsWide, height = pixels.pixelsHigh
  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  const rect = $.NSMakeRect(0, 0, width, height)
  const [red, green, blue] = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)

  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))
  source.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
  // Source atop paints only where the spark is, keeping its antialiased edges
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(red, green, blue, 1).set
  $.NSRectFillUsingOperation(rect, $.NSCompositingOperationSourceAtop)
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}
