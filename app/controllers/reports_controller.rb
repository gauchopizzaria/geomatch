class ReportsController < ApplicationController
  def create
    @report = Report.new(report_params)
    if @report.save
      redirect_to safety_center_path, notice: "Denúncia enviada com sucesso!"
    else
      render :new, alert: "Erro ao enviar denúncia."
    end
  end

  private

  def report_params
    # Permite a descrição e o array de fotos
    params.require(:report).permit(:description, photos: [])
  end
end