// Desenha o ícone do app (celular e seu reflexo de vidro sobre fundo azul) e grava um PNG de 1024 px.
// Uso: swiftc Tools/make-icon.swift -o build/make-icon && build/make-icon saida.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [r, g, b, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
  CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Base no formato dos ícones do macOS: 824 px centrados, cantos contínuos, azul em degradê.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.addPath(rounded(plate, 186))
ctx.clip()
ctx.drawLinearGradient(gradient([color(0.47, 0.70, 1.0), color(0.30, 0.50, 0.96), color(0.20, 0.36, 0.86)], [0, 0.55, 1]),
                       start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Brilho suave no topo da base.
ctx.drawRadialGradient(gradient([color(1, 1, 1, 0.22), color(1, 1, 1, 0)], [0, 1]),
                       startCenter: CGPoint(x: 360, y: 900), startRadius: 0,
                       endCenter: CGPoint(x: 360, y: 900), endRadius: 620, options: [])

// Celular de trás: sólido, azul-marinho, um pouco acima e à esquerda.
let back = CGRect(x: 262, y: 304, width: 330, height: 520)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 40, color: color(0.05, 0.08, 0.30, 0.45))
ctx.addPath(rounded(back, 66))
ctx.setFillColor(color(0.16, 0.18, 0.55))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(back, 66))
ctx.clip()
ctx.drawLinearGradient(gradient([color(0.26, 0.28, 0.72), color(0.13, 0.14, 0.46)], [0, 1]),
                       start: CGPoint(x: back.minX, y: back.maxY), end: CGPoint(x: back.maxX, y: back.minY), options: [])
ctx.restoreGState()
ctx.setStrokeColor(color(1, 1, 1, 0.18))
ctx.setLineWidth(6)
ctx.addPath(rounded(back.insetBy(dx: 3, dy: 3), 63))
ctx.strokePath()

// Celular da frente: vidro translúcido claro, deslocado para baixo e para a direita (o reflexo).
let front = CGRect(x: 432, y: 200, width: 330, height: 520)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 48, color: color(0.05, 0.10, 0.40, 0.40))
ctx.addPath(rounded(front, 66))
ctx.setFillColor(color(0.85, 0.91, 1.0, 0.42))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(front, 66))
ctx.clip()
ctx.drawLinearGradient(gradient([color(1, 1, 1, 0.45), color(1, 1, 1, 0.10)], [0, 1]),
                       start: CGPoint(x: front.minX, y: front.maxY), end: CGPoint(x: front.maxX, y: front.minY), options: [])
// Faixa de reflexo diagonal no vidro.
ctx.translateBy(x: front.midX, y: front.midY)
ctx.rotate(by: -.pi / 5)
ctx.setFillColor(color(1, 1, 1, 0.14))
ctx.fill(CGRect(x: -400, y: 60, width: 800, height: 70))
ctx.restoreGState()
ctx.setStrokeColor(color(1, 1, 1, 0.92))
ctx.setLineWidth(12)
ctx.addPath(rounded(front.insetBy(dx: 6, dy: 6), 60))
ctx.strokePath()

// Ilha da câmera no celular da frente.
ctx.setFillColor(color(1, 1, 1, 0.92))
ctx.addPath(rounded(CGRect(x: front.midX - 40, y: front.maxY - 58, width: 80, height: 18), 9))
ctx.fillPath()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
