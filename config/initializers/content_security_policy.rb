# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    # default_src: fallback para todas as directives não especificadas
    policy.default_src :self, :https

    # Fonts: Google Fonts + data URIs (local fonts)
    policy.font_src :self, :https, :data, "fonts.gstatic.com", "cdnjs.cloudflare.com"

    # Images: self + HTTPS + data URIs + Cloudinary
    policy.img_src :self, :https, :data, "res.cloudinary.com", "cdnjs.cloudflare.com"

    # Scripts: self + HTTPS + importmap + inline scripts com nonce + CDN permitidos
    policy.script_src :self, :https, "cdn.jsdelivr.net", "cdnjs.cloudflare.com", "unpkg.com"

    # Styles: self + HTTPS + inline styles com nonce + Google Fonts + CDN
    policy.style_src :self, :https, :unsafe_inline, "fonts.googleapis.com", "cdnjs.cloudflare.com", "unpkg.com"

    # Media: self + HTTPS
    policy.media_src :self, :https

    # Conexões (connect-src): API, WebSocket, Cloudinary, etc.
    policy.connect_src :self, :https, "res.cloudinary.com", "api.mapbox.com"

    # Objetos embutidos (Flash, etc): desabilitar
    policy.object_src :none

    # Frames: desabilitar (a menos que tenha embed de vídeo)
    policy.frame_src :none

    # Form submissions: apenas self
    policy.form_action :self

    # Base URI: apenas self
    policy.base_uri :self

    # Relatório de violações (optional — envia para um endpoint)
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
  # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
  config.content_security_policy_nonce_auto = true

  # Report violations without enforcing the policy (report-only mode — útil em staging).
  # config.content_security_policy_report_only = true
end
