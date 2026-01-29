# app/services/advanced_discovery_service.rb
class AdvancedDiscoveryService
  def initialize(user)
    @user = user
  end

  # Agora aceita um hash de opções (filters)
  def find_next_eligible_user(excluded_user_ids, filters = {})
    # Define padrões se os filtros não vierem: Distância 500km (se nil), Idade 18-100
    search_distance = filters[:distance].to_i > 0 ? filters[:distance].to_i : 500
    min_age = filters[:min_age]
    max_age = filters[:max_age]

    # 1. Constrói a query base: Localização (Dinâmica) e Exclusão
    # Usamos search_distance aqui em vez do 10 fixo
    base_query = User.near([@user.latitude, @user.longitude], search_distance)
                     .where.not(id: @user.id)
                     .where.not(id: excluded_user_ids)

    # 2. Aplica Filtro de Idade (NOVO)
    if min_age.present? && max_age.present?
      base_query = base_query.filter_by_age(min_age, max_age)
    end

    # 3. Aplica Filtro de Interesse (Gênero) existente
    interested_in = @user.interested_in
    generic_options = ["Outro", "Não-binário", "Prefiro não dizer", "Mulher", "Homem"]

    if interested_in.present? && !generic_options.include?(interested_in)
      base_query = base_query.where(gender: interested_in)
    end

    # 4. Carrega para memória
    base_users = base_query.to_a

    return nil, nil if base_users.empty?

    # 5. Filtro de Hobbies (Mantido igual)
    user_hobbies = @user.hobbies_list
    
    if user_hobbies.any?
      users_with_common_hobbies = base_users.select do |u|
        (u.hobbies_list & user_hobbies).any?
      end
      eligible_users = users_with_common_hobbies.any? ? users_with_common_hobbies : base_users
    else
      eligible_users = base_users
    end

    # 6. Seleciona aleatório e calcula distância
    next_user = eligible_users.sample

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