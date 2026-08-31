/// A locally captured file and, once uploaded, its private server asset ID.
///
/// The client ID is deliberately created before upload. Retrying an interrupted
/// upload is therefore safe: the server can recognise the same media asset.
enum MediaAttachmentType { image, audio }

class MediaAttachment {
  const MediaAttachment({
    required this.clientMediaId,
    required this.localPath,
    required this.type,
    this.remoteId,
  });

  final String clientMediaId;
  final String localPath;
  final MediaAttachmentType type;
  final String? remoteId;

  bool get uploaded => remoteId != null && remoteId!.isNotEmpty;

  MediaAttachment copyWith({String? remoteId}) => MediaAttachment(
    clientMediaId: clientMediaId,
    localPath: localPath,
    type: type,
    remoteId: remoteId ?? this.remoteId,
  );

  Map<String, Object?> toMap() => {
    'clientMediaId': clientMediaId,
    'localPath': localPath,
    'type': type.name,
    'remoteId': remoteId,
  };

  factory MediaAttachment.fromMap(Map<String, Object?> map) => MediaAttachment(
    clientMediaId: map['clientMediaId'] as String? ?? '',
    localPath: map['localPath'] as String? ?? '',
    type: MediaAttachmentType.values.firstWhere(
      (type) => type.name == map['type'],
      orElse: () => MediaAttachmentType.image,
    ),
    remoteId: map['remoteId'] as String?,
  );
}
