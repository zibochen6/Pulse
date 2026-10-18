import SwiftUI

/// Official DeepSeek mark from deepseek.com; see THIRD_PARTY_NOTICES.md.
struct DeepSeekProviderIcon: View {
  let size: CGFloat

  var body: some View {
    DeepSeekWhale()
      .fill(
        Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255), style: FillStyle(eoFill: false)
      )
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

private struct DeepSeekWhale: Shape {
  func path(in rect: CGRect) -> Path {
    // Original SVG viewBox: 0.163086 1.75 26.634 19.6. Preserve its aspect
    // ratio, subpath winding and all belly/eye cutouts without simplification.
    var path = Path()
    path.move(to: CGPoint(x: 26.5174, y: 3.39471))
    path.addCurve(
      to: CGPoint(x: 25.9487, y: 3.65346),
      control1: CGPoint(x: 26.235, y: 3.2567),
      control2: CGPoint(x: 26.1137, y: 3.52006))
    path.addCurve(
      to: CGPoint(x: 25.7969, y: 3.80469),
      control1: CGPoint(x: 25.8923, y: 3.69659),
      control2: CGPoint(x: 25.8446, y: 3.75294))
    path.addCurve(
      to: CGPoint(x: 24.2737, y: 4.49989),
      control1: CGPoint(x: 25.3846, y: 4.24516),
      control2: CGPoint(x: 24.9027, y: 4.53439))
    path.addCurve(
      to: CGPoint(x: 21.8735, y: 5.44119),
      control1: CGPoint(x: 23.3536, y: 4.44814),
      control2: CGPoint(x: 22.5682, y: 4.73737))
    path.addCurve(
      to: CGPoint(x: 20.4889, y: 3.72304),
      control1: CGPoint(x: 21.7258, y: 4.57349),
      control2: CGPoint(x: 21.2353, y: 4.0554))
    path.addCurve(
      to: CGPoint(x: 19.4297, y: 3.00197),
      control1: CGPoint(x: 20.0985, y: 3.55054),
      control2: CGPoint(x: 19.7034, y: 3.37746))
    path.addCurve(
      to: CGPoint(x: 19.091, y: 2.14289),
      control1: CGPoint(x: 19.2388, y: 2.73459),
      control2: CGPoint(x: 19.1865, y: 2.43673))
    path.addCurve(
      to: CGPoint(x: 18.7656, y: 1.75418),
      control1: CGPoint(x: 19.0301, y: 1.96579),
      control2: CGPoint(x: 18.9697, y: 1.78466))
    path.addCurve(
      to: CGPoint(x: 18.3705, y: 2.06067),
      control1: CGPoint(x: 18.5442, y: 1.71968),
      control2: CGPoint(x: 18.4574, y: 1.90541))
    path.addCurve(
      to: CGPoint(x: 17.9019, y: 4.10313),
      control1: CGPoint(x: 18.0232, y: 2.69549),
      control2: CGPoint(x: 17.8887, y: 3.39471))
    path.addCurve(
      to: CGPoint(x: 19.9421, y: 7.86834),
      control1: CGPoint(x: 17.9324, y: 5.6965),
      control2: CGPoint(x: 18.6051, y: 6.96556))
    path.addCurve(
      to: CGPoint(x: 20.0852, y: 8.22658),
      control1: CGPoint(x: 20.0939, y: 7.97184),
      control2: CGPoint(x: 20.133, y: 8.07535))
    path.addCurve(
      to: CGPoint(x: 19.7903, y: 9.15063),
      control1: CGPoint(x: 19.9938, y: 8.53766),
      control2: CGPoint(x: 19.8857, y: 8.83955))
    path.addCurve(
      to: CGPoint(x: 19.4257, y: 9.30588),
      control1: CGPoint(x: 19.7293, y: 9.34901),
      control2: CGPoint(x: 19.6384, y: 9.39271))
    path.addCurve(
      to: CGPoint(x: 17.4982, y: 7.99772),
      control1: CGPoint(x: 18.692, y: 8.9994),
      control2: CGPoint(x: 18.0583, y: 8.54571))
    path.addCurve(
      to: CGPoint(x: 14.6162, y: 5.26869),
      control1: CGPoint(x: 16.5477, y: 7.07827),
      control2: CGPoint(x: 15.6881, y: 6.06336))
    path.addCurve(
      to: CGPoint(x: 13.8521, y: 4.746),
      control1: CGPoint(x: 14.3644, y: 5.08296),
      control2: CGPoint(x: 14.1125, y: 4.91045))
    path.addCurve(
      to: CGPoint(x: 14.2816, y: 2.70814),
      control1: CGPoint(x: 12.7584, y: 3.68394),
      control2: CGPoint(x: 13.9952, y: 2.81164))
    path.addCurve(
      to: CGPoint(x: 13.4179, y: 2.23317),
      control1: CGPoint(x: 14.5812, y: 2.60003),
      control2: CGPoint(x: 14.3857, y: 2.22857))
    path.addCurve(
      to: CGPoint(x: 10.4359, y: 2.99335),
      control1: CGPoint(x: 12.4502, y: 2.2372),
      control2: CGPoint(x: 11.5646, y: 2.56151))
    path.addCurve(
      to: CGPoint(x: 9.91951, y: 3.14457),
      control1: CGPoint(x: 10.2708, y: 3.05832),
      control2: CGPoint(x: 10.0972, y: 3.10547))
    path.addCurve(
      to: CGPoint(x: 6.72069, y: 3.03245),
      control1: CGPoint(x: 8.8954, y: 2.95022),
      control2: CGPoint(x: 7.83162, y: 2.90709))
    path.addCurve(
      to: CGPoint(x: 1.72954, y: 5.94261),
      control1: CGPoint(x: 4.62877, y: 3.26533),
      control2: CGPoint(x: 2.95777, y: 4.25436))
    path.addCurve(
      to: CGPoint(x: 0.33167, y: 12.6824),
      control1: CGPoint(x: 0.254043, y: 7.97184),
      control2: CGPoint(x: -0.0932678, y: 10.2777))
    path.addCurve(
      to: CGPoint(x: 4.06008, y: 18.9558),
      control1: CGPoint(x: 0.778458, y: 15.2171),
      control2: CGPoint(x: 2.07225, y: 17.3153))
    path.addCurve(
      to: CGPoint(x: 11.2047, y: 21.3306),
      control1: CGPoint(x: 6.12152, y: 20.6567),
      control2: CGPoint(x: 8.49577, y: 21.4905))
    path.addCurve(
      to: CGPoint(x: 16.7473, y: 19.2669),
      control1: CGPoint(x: 12.8498, y: 21.2358),
      control2: CGPoint(x: 14.6812, y: 21.0155))
    path.addCurve(
      to: CGPoint(x: 18.7219, y: 19.7074),
      control1: CGPoint(x: 17.2682, y: 19.5262),
      control2: CGPoint(x: 17.8151, y: 19.6297))
    path.addCurve(
      to: CGPoint(x: 20.6143, y: 19.5648),
      control1: CGPoint(x: 19.4205, y: 19.7723),
      control2: CGPoint(x: 20.0933, y: 19.6729))
    path.addCurve(
      to: CGPoint(x: 21.0789, y: 18.4981),
      control1: CGPoint(x: 21.4302, y: 19.3923),
      control2: CGPoint(x: 21.3739, y: 18.6367))
    path.addCurve(
      to: CGPoint(x: 18.7351, y: 17.4706),
      control1: CGPoint(x: 18.6874, y: 17.3843),
      control2: CGPoint(x: 19.2124, y: 17.8374))
    path.addCurve(
      to: CGPoint(x: 22.379, y: 9.99821),
      control1: CGPoint(x: 19.9501, y: 16.033),
      control2: CGPoint(x: 21.8063, y: 13.4776))
    path.addCurve(
      to: CGPoint(x: 22.4986, y: 8.76192),
      control1: CGPoint(x: 22.4353, y: 9.61409),
      control2: CGPoint(x: 22.5072, y: 9.073))
    path.addCurve(
      to: CGPoint(x: 22.7545, y: 8.47671),
      control1: CGPoint(x: 22.494, y: 8.57216),
      control2: CGPoint(x: 22.5377, y: 8.49856))
    path.addCurve(
      to: CGPoint(x: 24.4692, y: 7.94999),
      control1: CGPoint(x: 23.3536, y: 8.40771),
      control2: CGPoint(x: 23.935, y: 8.24383))
    path.addCurve(
      to: CGPoint(x: 26.7911, y: 4.04678),
      control1: CGPoint(x: 26.0188, y: 7.10357),
      control2: CGPoint(x: 26.6439, y: 5.71318))
    path.addCurve(
      to: CGPoint(x: 26.5174, y: 3.39471),
      control1: CGPoint(x: 26.8129, y: 3.79204),
      control2: CGPoint(x: 26.7865, y: 3.52869))
    path.closeSubpath()
    path.move(to: CGPoint(x: 13.0143, y: 18.3946))
    path.addCurve(
      to: CGPoint(x: 9.10816, y: 15.9985),
      control1: CGPoint(x: 10.6964, y: 16.5724),
      control2: CGPoint(x: 9.5722, y: 15.9726))
    path.addCurve(
      to: CGPoint(x: 8.84768, y: 16.8449),
      control1: CGPoint(x: 8.67402, y: 16.0244),
      control2: CGPoint(x: 8.75222, y: 16.5212))
    path.addCurve(
      to: CGPoint(x: 9.25996, y: 17.6655),
      control1: CGPoint(x: 8.94773, y: 17.1646),
      control2: CGPoint(x: 9.07768, y: 17.3849))
    path.addCurve(
      to: CGPoint(x: 9.13404, y: 18.3348),
      control1: CGPoint(x: 9.38589, y: 17.8512),
      control2: CGPoint(x: 9.47272, y: 18.1272))
    path.addCurve(
      to: CGPoint(x: 7.0289, y: 18.1491),
      control1: CGPoint(x: 8.38766, y: 18.7965),
      control2: CGPoint(x: 7.08985, y: 18.1796))
    path.addCurve(
      to: CGPoint(x: 3.36546, y: 14.4793),
      control1: CGPoint(x: 5.51833, y: 17.2595),
      control2: CGPoint(x: 4.25559, y: 16.0853))
    path.addCurve(
      to: CGPoint(x: 1.92447, y: 9.50542),
      control1: CGPoint(x: 2.50581, y: 12.9337),
      control2: CGPoint(x: 2.0067, y: 11.2753))
    path.addCurve(
      to: CGPoint(x: 2.45406, y: 8.84932),
      control1: CGPoint(x: 1.90262, y: 9.07818),
      control2: CGPoint(x: 2.02855, y: 8.92695))
    path.addCurve(
      to: CGPoint(x: 4.15093, y: 8.80619),
      control1: CGPoint(x: 3.01413, y: 8.74582),
      control2: CGPoint(x: 3.59144, y: 8.72397))
    path.addCurve(
      to: CGPoint(x: 10.2185, y: 11.8848),
      control1: CGPoint(x: 6.51656, y: 9.15178),
      control2: CGPoint(x: 8.53027, y: 10.2092))
    path.addCurve(
      to: CGPoint(x: 12.6623, y: 15.0929),
      control1: CGPoint(x: 11.1822, y: 12.8388),
      control2: CGPoint(x: 11.9114, y: 13.979))
    path.addCurve(
      to: CGPoint(x: 15.4144, y: 18.3268),
      control1: CGPoint(x: 13.461, y: 16.2757),
      control2: CGPoint(x: 14.3201, y: 17.4027))
    path.addCurve(
      to: CGPoint(x: 16.404, y: 19.0783),
      control1: CGPoint(x: 15.8008, y: 18.6505),
      control2: CGPoint(x: 16.109, y: 18.8966))
    path.addCurve(
      to: CGPoint(x: 13.0143, y: 18.3958),
      control1: CGPoint(x: 15.5144, y: 19.1778),
      control2: CGPoint(x: 14.0297, y: 19.1991))
    path.addLine(to: CGPoint(x: 13.0143, y: 18.3946))
    path.closeSubpath()
    path.move(to: CGPoint(x: 14.1252, y: 11.2489))
    path.addCurve(
      to: CGPoint(x: 14.4679, y: 10.9079),
      control1: CGPoint(x: 14.1252, y: 11.0591),
      control2: CGPoint(x: 14.277, y: 10.9079))
    path.addCurve(
      to: CGPoint(x: 14.5852, y: 10.9292),
      control1: CGPoint(x: 14.511, y: 10.9079),
      control2: CGPoint(x: 14.5501, y: 10.9165))
    path.addCurve(
      to: CGPoint(x: 14.7111, y: 11.0114),
      control1: CGPoint(x: 14.6329, y: 10.9464),
      control2: CGPoint(x: 14.6766, y: 10.9723))
    path.addCurve(
      to: CGPoint(x: 14.8066, y: 11.2489),
      control1: CGPoint(x: 14.7721, y: 11.0718),
      control2: CGPoint(x: 14.8066, y: 11.158))
    path.addCurve(
      to: CGPoint(x: 14.4639, y: 11.5899),
      control1: CGPoint(x: 14.8066, y: 11.4386),
      control2: CGPoint(x: 14.6548, y: 11.5899))
    path.addCurve(
      to: CGPoint(x: 14.1252, y: 11.2489),
      control1: CGPoint(x: 14.273, y: 11.5899),
      control2: CGPoint(x: 14.1252, y: 11.4386))
    path.closeSubpath()
    path.move(to: CGPoint(x: 17.5759, y: 13.0188))
    path.addCurve(
      to: CGPoint(x: 16.9203, y: 13.1959),
      control1: CGPoint(x: 17.3545, y: 13.1096),
      control2: CGPoint(x: 17.1331, y: 13.1873))
    path.addCurve(
      to: CGPoint(x: 16.0348, y: 12.9153),
      control1: CGPoint(x: 16.5903, y: 13.2131),
      control2: CGPoint(x: 16.2303, y: 13.0791))
    path.addCurve(
      to: CGPoint(x: 15.423, y: 12.0734),
      control1: CGPoint(x: 15.7312, y: 12.6605),
      control2: CGPoint(x: 15.5139, y: 12.5179))
    path.addCurve(
      to: CGPoint(x: 15.4402, y: 11.4214),
      control1: CGPoint(x: 15.3839, y: 11.8837),
      control2: CGPoint(x: 15.4057, y: 11.5899))
    path.addCurve(
      to: CGPoint(x: 15.1757, y: 10.614),
      control1: CGPoint(x: 15.5185, y: 11.0585),
      control2: CGPoint(x: 15.4316, y: 10.8257))
    path.addCurve(
      to: CGPoint(x: 14.4115, y: 10.3938),
      control1: CGPoint(x: 14.9676, y: 10.4415),
      control2: CGPoint(x: 14.7025, y: 10.3938))
    path.addCurve(
      to: CGPoint(x: 14.1292, y: 10.3076),
      control1: CGPoint(x: 14.3029, y: 10.3938),
      control2: CGPoint(x: 14.2034, y: 10.3461))
    path.addCurve(
      to: CGPoint(x: 14.0033, y: 9.91023),
      control1: CGPoint(x: 14.0079, y: 10.2472),
      control2: CGPoint(x: 13.9078, y: 10.096))
    path.addCurve(
      to: CGPoint(x: 14.216, y: 9.67734),
      control1: CGPoint(x: 14.0338, y: 9.84985),
      control2: CGPoint(x: 14.1815, y: 9.70322))
    path.addCurve(
      to: CGPoint(x: 15.488, y: 9.6946),
      control1: CGPoint(x: 14.6111, y: 9.45251),
      control2: CGPoint(x: 15.0665, y: 9.52612))
    path.addCurve(
      to: CGPoint(x: 16.5989, y: 10.5623),
      control1: CGPoint(x: 15.8784, y: 9.85445),
      control2: CGPoint(x: 16.174, y: 10.1477))
    path.addCurve(
      to: CGPoint(x: 17.3585, y: 11.5772),
      control1: CGPoint(x: 17.033, y: 11.0631),
      control2: CGPoint(x: 17.1112, y: 11.2011))
    path.addCurve(
      to: CGPoint(x: 17.8536, y: 12.5185),
      control1: CGPoint(x: 17.554, y: 11.871),
      control2: CGPoint(x: 17.7317, y: 12.1729))
    path.addCurve(
      to: CGPoint(x: 17.5759, y: 13.0188),
      control1: CGPoint(x: 17.9272, y: 12.7341),
      control2: CGPoint(x: 17.8317, y: 12.9107))
    path.closeSubpath()
    let scale = min(rect.width / 26.634, rect.height / 19.6)
    return path.applying(
      CGAffineTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: rect.midX - 26.634 * scale / 2 - 0.163086 * scale,
        ty: rect.midY - 19.6 * scale / 2 - 1.75 * scale))
  }
}
