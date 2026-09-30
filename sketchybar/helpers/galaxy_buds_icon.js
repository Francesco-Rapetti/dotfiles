// Turns a photo of the Galaxy Buds on a transparent background into the icon of the audio items
// of SketchyBar, since SF Symbols only has earbuds by Apple and Beats: cropped to the buds, gray
// and lighter, since their black body would vanish on the dark bar
// Usage: osascript -l JavaScript galaxy_buds_icon.js <input png> <output png>

ObjC.import('AppKit')
ObjC.import('CoreImage')

// The bounds of the opaque pixels (y down), stepping by 2 px: reading a pixel from JXA is slow
function opaqueBounds(bitmap) {
  const width = bitmap.pixelsWide, height = bitmap.pixelsHigh
  const opaque = (x, y) => bitmap.colorAtXY(x, y).alphaComponent > 0.05
  const row = y => { for (let x = 0; x < width; x += 2) if (opaque(x, y)) return true; return false }
  const column = x => { for (let y = 0; y < height; y += 2) if (opaque(x, y)) return true; return false }
  let top = 0, bottom = height - 1, left = 0, right = width - 1
  while (top < bottom && !row(top)) top++
  while (bottom > top && !row(bottom)) bottom--
  while (left < right && !column(left)) left++
  while (right > left && !column(right)) right--
  return {left, top, width: right - left + 1, height: bottom - top + 1}
}

function run(argv) {
  const [input, output] = argv
  const data = $.NSData.dataWithContentsOfFile(input)
  const bounds = opaqueBounds($.NSBitmapImageRep.imageRepWithData(data))
  let image = $.CIImage.imageWithData(data)
  // Core Image counts y from the bottom
  const imageHeight = image.extent.size.height
  image = image.imageByCroppingToRect($.CGRectMake(bounds.left, imageHeight - bounds.top - bounds.height,
                                                   bounds.width, bounds.height))

  const gray = $.CIFilter.filterWithName('CIColorControls')
  gray.setValueForKey(image, 'inputImage')
  gray.setValueForKey($.NSNumber.numberWithDouble(0), 'inputSaturation')
  // Black becomes a light gray and the rest follows, keeping the shading of the photo
  const lighter = $.CIFilter.filterWithName('CIToneCurve')
  lighter.setValueForKey(gray.outputImage, 'inputImage')
  const curve = [[0, 0.5], [0.25, 0.68], [0.5, 0.82], [0.75, 0.93], [1, 1]]
  curve.forEach(([x, y], i) => lighter.setValueForKey($.CIVector.vectorWithXY(x, y), `inputPoint${i}`))

  const bitmap = $.NSBitmapImageRep.alloc.initWithCIImage(lighter.outputImage)
  bitmap.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $()).writeToFileAtomically(output, true)
}
