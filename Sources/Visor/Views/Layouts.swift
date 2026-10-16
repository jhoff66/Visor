import SwiftUI

/// Itens em linha que quebram para a próxima quando não cabem.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8

  private func rows(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
    var frames: [CGRect] = []
    var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
    for sub in subviews {
      let s = sub.sizeThatFits(.unspecified)
      if x > 0, x + s.width > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
      frames.append(CGRect(x: x, y: y, width: s.width, height: s.height))
      x += s.width + spacing
      maxX = max(maxX, x - spacing)
      lineHeight = max(lineHeight, s.height)
    }
    return (frames, CGSize(width: maxX, height: y + lineHeight))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    rows(subviews, width: proposal.width ?? .infinity).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let r = rows(subviews, width: bounds.width)
    for (sub, f) in zip(subviews, r.frames) {
      sub.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
    }
  }
}

/// Grade adaptativa em que os cartões de uma mesma linha têm a mesma altura.
struct CardGrid: Layout {
  var minimum: CGFloat = 300
  var spacing: CGFloat = 16

  private func columns(for width: CGFloat) -> Int {
    guard width.isFinite else { return 1 }
    return max(1, Int((width + spacing) / (minimum + spacing)))
  }

  private func layout(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
    let cols = columns(for: width)
    let w = width.isFinite ? (width - spacing * CGFloat(cols - 1)) / CGFloat(cols) : minimum
    var frames: [CGRect] = []
    var y: CGFloat = 0
    var i = 0
    while i < subviews.count {
      let row = Array(subviews[i..<min(i + cols, subviews.count)])
      let rowHeight = row.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
      for (c, _) in row.enumerated() {
        frames.append(CGRect(x: CGFloat(c) * (w + spacing), y: y, width: w, height: rowHeight))
      }
      y += rowHeight + spacing
      i += cols
    }
    return (frames, max(0, y - spacing))
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? minimum
    return CGSize(width: width, height: layout(subviews, width: width).height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let r = layout(subviews, width: bounds.width)
    for (sub, f) in zip(subviews, r.frames) {
      sub.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                proposal: ProposedViewSize(width: f.width, height: f.height))
    }
  }
}
