// Draws the icons of the Wi-Fi networks in the popup of network.sh: the wifi SF Symbol with one, two
// or three bars lit as in the macOS menu, the others dimmed, as SF Symbols draws its variable value.
// The rows have the name after the icon and a text on the right, so the icon has to be an image, as
// in the popup of audio.sh. SketchyBar can't color images, so the color is baked in
// Usage: osascript -l JavaScript network_icons.js <output directory> <RRGGBB>
// which writes wifi_1.png, wifi_2.png and wifi_3.png

ObjC.import('AppKit')

// As big as the SF Symbols of the bar (SF Pro Semibold 14), at 4 px per point as network.sh expects.
// JXA has neither NSFontWeightSemibold nor NSImageSymbolScaleMedium, hence their values. The
// variable value of wifi lights the dot above 0, the first arc above a third and the second above
// two thirds
const SIZE = 14, SCALE = 4, SEMIBOLD = 0.3, MEDIUM = 2
const LEVELS = {1: 0.1, 2: 0.5, 3: 1}

function draw(image, hex, output) {
  const width = Math.ceil(image.size.width), height = Math.ceil(image.size.height)
  const bitmap = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, width, height, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0)
  const rect = $.NSMakeRect(0, 0, width, height)
  const [red, green, blue] = [0, 2, 4].map(i => parseInt(hex.substr(i, 2), 16) / 255)

  $.NSGraphicsContext.saveGraphicsState
  $.NSGraphicsContext.setCurrentContext($.NSGraphicsContext.graphicsContextWithBitmapImageRep(bitmap))
  image.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1)
  // Source atop paints only where the image is, keeping its antialiased edges and the dimmed bars
  $.NSColor.colorWithSRGBRedGreenBlueAlpha(red, green, blue, 1).set
  $.NSRectFillUsingOperation(rect, $.NSCompositingOperationSourceAtop)
  $.NSGraphicsContext.restoreGraphicsState

  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}

function run(argv) {
  const [directory, hex] = argv
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(directory, true, $(), null)
  const configuration = $.NSImageSymbolConfiguration.configurationWithPointSizeWeightScale(SIZE * SCALE, SEMIBOLD, MEDIUM)
  for (const [level, value] of Object.entries(LEVELS)) {
    const image = $.NSImage.imageWithSystemSymbolNameVariableValueAccessibilityDescription('wifi', value, $())
      .imageWithSymbolConfiguration(configuration)
    draw(image, hex, `${directory}/wifi_${level}.png`)
  }
}
