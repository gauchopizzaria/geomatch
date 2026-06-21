module SeoHelper
  # Gera JSON-LD para SoftwareApplication (Google, Bing, schema.org)
  def schema_application_json
    {
      "@context": "https://schema.org/",
      "@type": "SoftwareApplication",
      "name": "GeoMatch",
      "description": "Conecte-se com pessoas reais a até 300 metros de você em tempo real. Chat instantâneo, mapa interativo e segurança em primeiro lugar.",
      "applicationCategory": "SocialNetworkingApplication",
      "operatingSystem": ["iOS", "Android"],
      "offers": [
        {
          "@type": "Offer",
          "price": "0",
          "priceCurrency": "BRL",
          "name": "GeoMatch Free"
        },
        {
          "@type": "Offer",
          "price": "47.90",
          "priceCurrency": "BRL",
          "name": "GeoMatch Gold"
        }
      ],
      "aggregateRating": {
        "@type": "AggregateRating",
        "ratingValue": "4.8",
        "ratingCount": "1250"
      },
      "url": "https://geomatchbr.com",
      "downloadUrl": [
        "https://testflight.apple.com/join/d2WGpc3D",
        "https://play.google.com/store/apps/details?id=com.geomatch.app"
      ],
      "image": image_url("logo-geomatch.svg"),
      "author": {
        "@type": "Organization",
        "name": "GeoMatch Inc.",
        "url": "https://geomatchbr.com"
      }
    }
  end

  # Renderiza JSON-LD como <script type="application/ld+json">
  def render_schema_json
    tag.script(schema_application_json.to_json, type: "application/ld+json")
  end

  # Gera metatags Open Graph + Twitter Card
  def page_meta_tags(title: nil, description: nil, image: nil, url: nil)
    {
      title: title || "GeoMatch — Conecte-se com pessoas reais perto de você",
      description: description || "Veja quem está a até 300 metros de você em tempo real. Chat instantâneo, mapa interativo, segurança em primeiro lugar.",
      image: image || image_url("logo-geomatch.svg"),
      url: url || request.url,
      og_title: title || "GeoMatch",
      og_description: description || "Conecte-se com pessoas reais a 300 metros de você.",
      og_image: image || image_url("logo-geomatch.svg"),
      og_type: "website",
      tw_card: "summary_large_image",
      tw_title: title || "GeoMatch",
      tw_description: description || "Conecte-se com pessoas reais perto de você.",
      tw_image: image || image_url("logo-geomatch.svg")
    }
  end

  # Renderiza metatags no layout
  def render_page_meta_tags(meta_hash)
    tags = []

    # Título da página (já gerenciado pelo Rails via <title>)

    # Description
    tags << tag.meta(name: "description", content: meta_hash[:description])
    tags << tag.meta(name: "theme-color", content: "#F4DFC4")

    # Open Graph (Facebook, LinkedIn)
    tags << tag.meta(property: "og:title", content: meta_hash[:og_title])
    tags << tag.meta(property: "og:description", content: meta_hash[:og_description])
    tags << tag.meta(property: "og:image", content: meta_hash[:og_image])
    tags << tag.meta(property: "og:type", content: meta_hash[:og_type])
    tags << tag.meta(property: "og:url", content: meta_hash[:url])

    # Twitter Card
    tags << tag.meta(name: "twitter:card", content: meta_hash[:tw_card])
    tags << tag.meta(name: "twitter:title", content: meta_hash[:tw_title])
    tags << tag.meta(name: "twitter:description", content: meta_hash[:tw_description])
    tags << tag.meta(name: "twitter:image", content: meta_hash[:tw_image])

    # Canonical URL
    tags << tag.link(rel: "canonical", href: meta_hash[:url])

    # Keywords (opcional, mas bom ter)
    tags << tag.meta(name: "keywords", content: "geolocalização, mapa, chat, conexões, pessoas próximas, aplicativo")

    tags.join("\n").html_safe
  end
end
