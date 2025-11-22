# config/initializers/active_storage_r2_fix.rb

# Garante que a classe S3Service seja carregada antes de tentar modificá-la.
require "active_storage/service/s3_service"

# Esta correção é necessária porque o Cloudflare R2 (e algumas versões do AWS SDK)
# não suportam o parâmetro :checksum_algorithm que o Active Storage tenta passar.
if defined?(ActiveStorage::Service::S3Service)
  ActiveStorage::Service::S3Service.class_eval do
    # Sobrescreve o método de upload para filtrar o parâmetro problemático.
    def upload(key, io, checksum: nil, **options)
      # Remove o parâmetro :checksum_algorithm das opções antes de chamar o método original (super)
      options.delete(:checksum_algorithm)
      super(key, io, checksum: checksum, **options)
    end
  end
end
