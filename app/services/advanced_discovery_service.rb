# app/services/advanced_discovery_service.rb
class AdvancedDiscoveryService
  def initialize(user)
    @user = user
  end

  # Retorna o próximo usuário elegível (User object) e sua distância (Float)
  def find_next_eligible_user(excluded_user_ids)
    # 1. Constrói a query base: Localização e Exclusão
    base_query = User.near([@user.latitude, @user.longitude], 10)
                     .where.not(id: @user.id)
                     .where.not(id: excluded_user_ids)

    # 2. Aplica Filtro de Interesse (Gênero) com a nova lógica
    interested_in = @user.interested_in
    generic_options = ["Outro", "Não-binário", "Prefiro não dizer", "Mulher", "Homem"]

    if interested_in.present? && !generic_options.include?(interested_in)
    base_query = base_query.where(gender: interested_in)
    end
    # Se o interesse estiver na lista show_all_genders ou for nulo, nenhum filtro de gênero é aplicado, mostrando todos os usuários.

    # 3. Carrega os usuários elegíveis para a memória (apenas os necessários)
    base_users = base_query.to_a

    # Se não houver usuários após o filtro de interesse, retorna nil
    return nil, nil if base_users.empty?

    # 4. Filtro de Hobbies em Comum (Filtro Primário - em memória)
    user_hobbies = @user.hobbies_list
    
    if user_hobbies.any?
      # Tenta encontrar usuários que compartilham pelo menos um hobby
      users_with_common_hobbies = base_users.select do |u|
        (u.hobbies_list & user_hobbies).any?
      end
      
      # Se encontrar, usa apenas esses usuários. Caso contrário, usa todos os usuários base.
      eligible_users = users_with_common_hobbies.any? ? users_with_common_hobbies : base_users
    else
      # Se o usuário atual não tem hobbies, usa todos os usuários base
      eligible_users = base_users
    end

    # 5. Seleciona um usuário aleatório
    next_user = eligible_users.sample

    # 6. Calcula a distância e retorna
    if next_user
      distance = Geocoder::Calculations.distance_between(
        [@user.latitude, @user.longitude],
        [next_user.latitude, next_user.longitude]
      ).round(1)
      return next_user, distance
    else
      return nil, nil
    end
  end
end
