import '../domain/facility.dart';

const notInformed = 'Não informado';
const notConfirmed = 'Informação não confirmada';

String natureLabel(AdministrativeNature nature) => switch (nature) {
  AdministrativeNature.public => 'Pública',
  AdministrativeNature.private => 'Privada',
  AdministrativeNature.unknown => 'Natureza não informada',
};

String susLabel(TriState sus) => switch (sus) {
  TriState.yes => 'Atende pelo SUS',
  TriState.no => 'Sem atendimento SUS no cadastro',
  TriState.unknown => 'Atendimento SUS: não informado',
};

String h24Label(TriState value) => switch (value) {
  TriState.yes => 'Funciona 24 horas',
  TriState.no => 'Não funciona 24 horas',
  TriState.unknown => 'Funcionamento 24h: não informado',
};

String triLabel(TriState value) => switch (value) {
  TriState.yes => 'Sim',
  TriState.no => 'Não',
  TriState.unknown => notInformed,
};

String reviewLabel(Facility f) => switch (f.reviewStatus) {
  ReviewStatus.approved => 'Conferido pela curadoria',
  ReviewStatus.pending => 'Dados de cadastro, não confirmados pela curadoria',
};
