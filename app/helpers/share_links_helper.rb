module ShareLinksHelper
  # A QR of the share link, drawn in the app (D-share-link): handing your
  # phone across a kitchen — or a recipe to someone standing next to you —
  # shouldn't need a third-party image service, an internet connection, or
  # sending the token to anybody. rqrcode renders SVG locally.
  #
  # Deliberately high-contrast rather than themed: a scanner needs dark on
  # white, not sand on cream.
  def share_link_qr(url, size: 4)
    RQRCode::QRCode.new(url.to_s, level: :m)
      .as_svg(module_size: size, use_path: true, viewbox: true, color: "1c1917", fill: "ffffff")
      .html_safe
  rescue RQRCodeCore::QRCodeRunTimeError
    nil
  end
end
