// Draws the plug of the battery item of SketchyBar, shown while the Mac is plugged in but not
// charging, in each color battery.sh gives it. The SF Symbols of the other states are text in the
// SF Pro font, but the plug is drawn by its name, since the font has no name for its glyphs.
// SketchyBar can't color images, so the color is baked in
// Usage: osascript -l JavaScript battery_icons.js <output directory> <name>=<RRGGBB>...
// which writes plug_<name>.png, e.g. plug_green.png

ObjC.import('AppKit')

// powerplug, as big as the SF Symbols of the bar (SF Pro Semibold 14), at 4 px per point as
// battery.sh expects. JXA has neither NSFontWeightSemibold nor NSImageSymbolScaleMedium, hence
// their values
const SYMBOL = 'powerplug', SIZE = 14, SCALE = 4, SEMIBOLD = 0.3, MEDIUM = 2

function plug(hex, output) {
  const configuration = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(SIZE * SCALE, SEMIBOLD, MEDIUM)
  const symbol = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(SYMBOL, $())
    .imageWithSymbolConfiguration(configuration)
  const width = Math.ceil(symbol.size.width), height = Math.ceil(symbol.size.height)
  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  const rect = $.NSMakeRect(0, 0, width, height)
  const [red, green, blue] = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)

  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))
  symbol.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
  // Source atop paints only where the symbol is, keeping its antialiased edges
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(red, green, blue, 1).set
  $.NSRectFillUsingOperation(rect, $.NSCompositingOperationSourceAtop)
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}

function run(argv) {
  const [directory, ...colors] = argv
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null)
  for (const color of colors) {
    const [name, hex] = color.split('=')
    plug(hex, `${directory}/plug_${name}.png`)
  }
}
