# Confere que o XAML carrega. Um XAML quebrado so reclama em tempo de
# execucao, e o erro do XamlReader e ilegivel - melhor pegar aqui.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$caminho = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'janela.xaml'
try {
    $xml = [xml](Get-Content $caminho -Raw)
    $leitor = New-Object System.Xml.XmlNodeReader $xml
    $janela = [Windows.Markup.XamlReader]::Load($leitor)
    "XAML carregou: " + $janela.Title + "  " + $janela.Width + "x" + $janela.Height
    foreach ($n in @('imgLogo','luzEstado','txtEstadoTopo','areaConteudo','txtRodape',
                     'mnuSituacao','mnuProtegido','mnuExecutar','mnuRestaurar','mnuConfig')) {
        $el = $janela.FindName($n)
        "  {0,-16} {1}" -f $n, $(if ($el) { 'ok' } else { 'NAO ENCONTRADO' })
    }
} catch {
    "FALHOU: " + $_.Exception.Message
    if ($_.Exception.InnerException) { "  interno: " + $_.Exception.InnerException.Message }
}
