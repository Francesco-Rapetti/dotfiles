// Draws the icons of the home items of SketchyBar and of the rows of their popup: the SF Symbols of
// home.sh, by name, and the logo of Home Assistant, in each color it gives them. SketchyBar can't
// color images, so the color is baked in; the rows have the name after the icon and the state on
// the right, so the icon has to be an image, as in the popup of audio.sh.
// The logo is the one Home Assistant gives Safari for pinned tabs (/static/icons/mask-icon.svg), a
// single color with the circuit cut out, which sketchybarrc downloads from the server: it is a
// trademark, so it isn't in the repo. Without it there is no logo, and home.sh shows a house
// Usage: osascript -l JavaScript home_assistant_icons.js <output directory> <logo svg> <name>=<RRGGBB>...
// which writes <symbol>_<name>.png for each symbol and color, e.g. lightbulb.fill_yellow.png, and
// logo_<name>.png

ObjC.import('AppKit')

const SYMBOLS = [
  'house.fill',
  'printer.fill',
  'lightbulb.fill',
  'lightbulb',
  'powerplug.fill',
  'roller.shade.open',
  'roller.shade.closed',
  'flame.fill',
  'snowflake',
  'humidity.fill',
  'fan.fill',
  'thermometer.medium',
  'robotic.vacuum.fill',
  'play.fill',
]

// As big as the SF Symbols of the bar (SF Pro Semibold 14), at 4 px per point as home.sh expects.
// JXA has neither NSFontWeightSemibold nor NSImageSymbolScaleMedium, hence their values. The logo,
// a solid square, is a bit taller than the symbols, whose ink is lighter
const SIZE = 14, LOGO_SIZE = 15, SCALE = 4, SEMIBOLD = 0.3, MEDIUM = 2

function draw(image, width, height, hex, output) {
  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  const rect = $.NSMakeRect(0, 0, width, height)
  const [red, green, blue] = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)

  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))
  image.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
  // Source atop paints only where the image is, keeping its antialiased edges
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(red, green, blue, 1).set
  $.NSRectFillUsingOperation(rect, $.NSCompositingOperationSourceAtop)
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}

function run(argv) {
  const [directory, logoFile, ...colors] = argv
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null)
  const configuration = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(SIZE * SCALE, SEMIBOLD, MEDIUM)
  const symbols = SYMBOLS.map(name => [name, $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(name, $())
    .imageWithSymbolConfiguration(configuration)])
  const logo = $.NSImage.alloc.initWithContentsOfFile(logoFile)
  for (const color of colors) {
    const [name, hex] = color.split('=')
    for (const [symbol, image] of symbols) {
      draw(image, Math.ceil(image.size.width), Math.ceil(image.size.height), hex, `${directory}/${symbol}_${name}.png`)
    }
    if (!logo.isNil()) draw(logo, LOGO_SIZE * SCALE, LOGO_SIZE * SCALE, hex, `${directory}/logo_${name}.png`)
  }
}
