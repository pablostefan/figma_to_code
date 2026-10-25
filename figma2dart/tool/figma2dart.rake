# Tarefa do figma2dart para o Rakefile do monorepo: `rake figma2dart:setup`.
# Copie para `rakelib/figma2dart.rake` (o rake carrega sozinho) ou cole no Rakefile.
# Sem caminho fixo: acha a CLI pelo índice do git, como o próprio comando figma2dart.
require 'json'

namespace :figma2dart do
  desc 'Põe o comando figma2dart no PATH (uma vez por máquina; rodar de novo só reinstala)'
  task :setup do
    root = `git rev-parse --show-toplevel`.chomp
    abort 'figma2dart: rode dentro do repositório git.' unless $?.success?
    main = `git -C "#{root}" ls-files ":(glob)**/bin/figma2dart.dart"`.lines.first&.chomp
    abort 'figma2dart: CLI não encontrada no repositório (nenhum bin/figma2dart.dart no git).' if main.to_s.empty?

    script = File.join(root, main.delete_suffix('bin/figma2dart.dart'), 'tool', 'figma2dart')
    out = `"#{script}" setup` # o pub get da CLI, quando roda, sai no stderr (aparece no terminal)
    abort 'figma2dart: setup falhou (veja a saída acima).' unless $?.success?

    result = JSON.parse(out)
    puts "figma2dart instalado em #{result['installed']} (CLI: #{result['fallback']})"
    puts "Adicione ao PATH: export PATH=\"$PATH:#{File.dirname(result['installed'])}\"" unless result['inPath']
  end
end
