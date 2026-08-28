module AboutHelper
  # Render a registered screenshot, or nothing at all.
  #
  # Nothing at all is the important half. The images are produced by a
  # capture run against the demo household (`bin/rails screenshots:capture`)
  # rather than written by hand, so a checkout can legitimately be without
  # one — a shot added to the registry before the next capture, or a clone
  # that hasn't run it. A missing file must degrade to an absent figure, not
  # to a broken image on a public page.
  def about_screenshot(name, caption: nil)
    shot = About::Shot.find(name)
    return if shot.nil? || !About::Shot.directory.join("#{shot.name}.webp").exist?

    tag.figure(class: "mt-8") do
      image_tag(shot.filename, alt: caption || shot.caption, loading: "lazy",
        class: "w-full rounded-2xl border border-edge") +
        tag.figcaption(caption || shot.caption, class: "mt-2 text-xs text-soft")
    end
  end
end
