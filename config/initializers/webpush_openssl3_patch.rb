# Patch para compatibilidade entre a gem webpush 1.1.0 e OpenSSL 3.0.
#
# Problema: em OpenSSL 3.0 (Ruby 3.2+), objetos PKey são imutáveis após
# criação. O webpush chama `ec.generate_key` e depois tenta sobrescrever
# as chaves via `curve.public_key = point` e `curve.private_key = bn`,
# o que lança OpenSSL::PKey::PKeyError "pkeys are immutable".
#
# Solução: reconstruímos os dois métodos problemáticos usando a API
# OpenSSL::PKey.read com DER (SEC1 + PKCS#8), que é a forma correta
# de criar chaves EC imutáveis no OpenSSL 3.0.
module Webpush
  class VapidKey
    # Corrige a geração de chave nova (VapidKey.generate / VapidKey.new).
    # OpenSSL::PKey::EC.generate é o método moderno e retorna um objeto
    # já finalizado, compatível com OpenSSL 3.0.
    def initialize
      @curve = OpenSSL::PKey::EC.generate("prime256v1")
    end

    # Corrige o carregamento de chaves existentes (VapidKey.from_keys).
    # Usa `allocate` para pular `initialize` (evitando a geração de chaves
    # aleatórias que nunca serão usadas) e constrói o objeto EC via DER.
    def self.from_keys(public_key, private_key)
      instance = allocate

      group   = OpenSSL::PKey::EC::Group.new("prime256v1")
      pub_bn  = OpenSSL::BN.new(Webpush.decode64(public_key), 2)
      priv_bn = OpenSSL::BN.new(Webpush.decode64(private_key), 2)

      pub_bytes  = OpenSSL::PKey::EC::Point.new(group, pub_bn).to_octet_string(:uncompressed)
      priv_bytes = [priv_bn.to_s(16).rjust(64, "0")].pack("H*")

      # SEC1 ECPrivateKey (RFC 5915)
      sec1_der = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer(1),
        OpenSSL::ASN1::OctetString(priv_bytes),
        OpenSSL::ASN1::Constructive(
          [OpenSSL::ASN1::ObjectId("prime256v1")], 0, :CONTEXT_SPECIFIC
        ),
        OpenSSL::ASN1::Constructive(
          [OpenSSL::ASN1::BitString(pub_bytes)], 1, :CONTEXT_SPECIFIC
        )
      ]).to_der

      # PKCS#8 PrivateKeyInfo (RFC 5958) — formato que OpenSSL::PKey.read aceita
      pkcs8_der = OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::Integer(0),
        OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::ObjectId("id-ecPublicKey"),
          OpenSSL::ASN1::ObjectId("prime256v1")
        ]),
        OpenSSL::ASN1::OctetString(sec1_der)
      ]).to_der

      instance.instance_variable_set(:@curve, OpenSSL::PKey.read(pkcs8_der))
      instance
    end
  end
end
