# config/initializers/active_storage_r2_fix.rb

# 1. Define o serviço de armazenamento para :r2 (substituindo a linha comentada no production.rb)
Rails.application.config.active_storage.service = :r2

# 2. Garante que a classe S3Service seja carregada.
require "active_storage/service/s3_service"

# 3. Aplica o monkey-patch para contornar o erro do AWS SDK antigo.
if defined?(ActiveStorage::Service::S3Service)
  ActiveStorage::Service::S3Service.class_eval do
    def upload(key, io, checksum: nil, **options)
      # Remove o parâmetro :checksum_algorithm das opções antes de chamar o método put_object.
      options.delete(:checksum_algorithm)
      
      # Usa a lógica de upload do Active Storage, chamando o cliente S3.
      instrument :upload, key: key, checksum: checksum do
        begin
          client.put_object(
            bucket: bucket,
            key: key,
            body: io,
            content_md5: checksum,
            **options
          )
        rescue Aws::S3::Errors::BadDigest
          raise ActiveStorage::IntegrityError
        end
      end
    end
  end
end
