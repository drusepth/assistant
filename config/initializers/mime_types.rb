# The install manifest has its own media type in the spec, and serving it as
# plain application/json is the kind of thing that works in every browser
# until it meets the one proxy that content-types by what it was told. This
# also gives the template a format to be found under: Rails' PwaController
# renders `pwa/manifest` with whatever format the request negotiated, and a
# browser fetching a manifest sends `Accept: */*`, which Rails resolves to
# :html — so without a format pinned on the route, the JSON template is
# simply never found.
Mime::Type.register "application/manifest+json", :webmanifest
