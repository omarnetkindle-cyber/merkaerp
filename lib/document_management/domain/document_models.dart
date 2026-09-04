enum DocumentDirection { incoming, outgoing, internal }

enum DocumentAccessLevel { public, classified, reserved, personalData }

enum DocumentCaseStatus { open, closed, transferred, disposed }

enum FinalDisposition { totalConservation, selection, elimination, reproduction }

extension DocumentDirectionWire on DocumentDirection {
  String get wire => switch (this) {
        DocumentDirection.incoming => 'incoming',
        DocumentDirection.outgoing => 'outgoing',
        DocumentDirection.internal => 'internal',
      };

  String get label => switch (this) {
        DocumentDirection.incoming => 'Recibido',
        DocumentDirection.outgoing => 'Enviado',
        DocumentDirection.internal => 'Interno',
      };
}

class DocumentDashboardSnapshot {
  const DocumentDashboardSnapshot({
    required this.today,
    required this.pending,
    required this.overdue,
    required this.forSignature,
    required this.openCases,
    required this.activeLoans,
    required this.transfersPending,
  });
  final int today;
  final int pending;
  final int overdue;
  final int forSignature;
  final int openCases;
  final int activeLoans;
  final int transfersPending;
}

class RadicadoInput {
  const RadicadoInput({
    required this.direction,
    required this.subject,
    required this.senderName,
    required this.recipientName,
    this.description,
    this.documentClass = 'correspondence',
    this.channel = 'digital',
    this.priority = 'normal',
    this.accessLevel = 'public',
    this.termBusinessDays,
    this.assignedDependencyId,
    this.assignedUserId,
    this.responseToId,
    this.metadata = const {},
  });

  final DocumentDirection direction;
  final String subject;
  final String senderName;
  final String recipientName;
  final String? description;
  final String documentClass;
  final String channel;
  final String priority;
  final String accessLevel;
  final int? termBusinessDays;
  final int? assignedDependencyId;
  final String? assignedUserId;
  final int? responseToId;
  final Map<String, Object?> metadata;
}

class CreatedRadicado {
  const CreatedRadicado({required this.id, required this.number, this.dueAt});
  final int id;
  final String number;
  final DateTime? dueAt;
}
