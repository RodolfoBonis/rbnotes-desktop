/// Caminhos da aplicação (master-detail: lista fixa + detalhe roteado).
abstract final class Routes {
  static const home = '/';
  static const settings = '/settings';
  static const notePattern = '/notes/:id';

  static String note(String id) => '/notes/$id';
}
