// Draws the icons of the docker item of SketchyBar and of the rows of its popup: the whale of Docker
// Desktop for the bar, and the SF Symbols of docker.sh, by name, in each color it gives them.
// SketchyBar can't color images, so the color is baked in; the rows have the name after the icon
// and the usage on the right, so the icon has to be an image, as in the popup of system.sh.
// The whale is the one of Docker Desktop's asset catalog, a single gray: it is a trademark, so
// neither it nor the image are in the repo. Without Docker Desktop, e.g. with colima, there is no
// whale and docker.sh shows a box
// Usage: osascript -l JavaScript docker_icons.js <output directory> <Docker.app> <whale RRGGBB> <name>=<RRGGBB>...
// which writes whale.png and <symbol>_<name>.png for each symbol and color, e.g.
// circle.fill_green.png

ObjC.import('AppKit')

const SYMBOLS = [
  'shippingbox.fill',
  'circle.fill',
  'pause.circle.fill',
  'arrow.clockwise.circle.fill',
  'exclamationmark.circle.fill',
]

// At 4 px per point, as docker.sh expects. The box is as big as the SF Symbols of the bar (SF Pro
// Semibold 14), the symbols of the rows smaller, as a badge next to the name. The whale, much wider
// than tall, is a bit shorter than the symbols, whose ink is lighter. JXA has neither
// NSFontWeightSemibold nor NSImageSymbolScaleMedium, hence their values
const BAR_SIZE = 14, ROW_SIZE = 11, WHALE_HEIGHT = 12, SCALE = 4, SEMIBOLD = 0.3, MEDIUM = 2

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

function symbol(name, size) {
  const configuration = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(size * SCALE, SEMIBOLD, MEDIUM)
  return $.NSImage.imageWithSystemSymbolNameAccessibilityDescription(name, $()).imageWithSymbolConfiguration(configuration)
}

function run(argv) {
  const [directory, app, whaleHex, ...colors] = argv
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null)

  const bundle = $.NSBundle.bundleWithPath(app)
  const whale = bundle.isNil() ? $() : bundle.imageForResource('Whale')
  if (!whale.isNil()) {
    const height = WHALE_HEIGHT * SCALE
    draw(whale, Math.round(height * whale.size.width / whale.size.height), height, whaleHex, `${directory}/whale.png`)
  } else {
    $.NSFileManager.defaultManager.removeItemAtPathError(`${directory}/whale.png`, null)
  }

  for (const color of colors) {
    const [name, hex] = color.split('=')
    for (const symbolName of SYMBOLS) {
      const image = symbol(symbolName, symbolName === 'shippingbox.fill' ? BAR_SIZE : ROW_SIZE)
      draw(image, Math.ceil(image.size.width), Math.ceil(image.size.height), hex, `${directory}/${symbolName}_${name}.png`)
    }
  }
}
