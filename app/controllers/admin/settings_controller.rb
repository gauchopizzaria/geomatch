class Admin::SettingsController < Admin::BaseController
  SETTING_META = {
    'one_off_message_price' => {
      label:       'Preço da Mensagem Avulsa',
      description: 'Valor cobrado por mensagem avulsa para usuários do plano Free.',
      type:        :price
    }
  }.freeze

  def index
    @settings = Setting.order(:key).map do |s|
      meta = SETTING_META[s.key] || { label: s.key.humanize, description: '', type: :integer }
      { setting: s, label: meta[:label], description: meta[:description], type: meta[:type] }
    end
  end

  def update
    @setting = Setting.find(params[:id])
    meta      = SETTING_META[@setting.key] || { type: :integer }
    raw       = params.dig(:setting, :value).to_s.strip
    new_value = meta[:type] == :price ? parse_price_to_cents(raw) : raw.to_i

    if @setting.update(value: new_value)
      redirect_to admin_settings_path, notice: "Configuração atualizada com sucesso!"
    else
      redirect_to admin_settings_path, alert: "Erro: #{@setting.errors.full_messages.join(', ')}"
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_settings_path, alert: "Configuração não encontrada."
  end

  private

  def parse_price_to_cents(raw)
    # Accepts Brazilian format: "1,99" → 199
    (raw.tr(',', '.').to_f * 100).round
  end
end
