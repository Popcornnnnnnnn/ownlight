export interface AudioSummaryAnchorCandidate {
  id: string;
  sortOrder: number;
}

export interface ReadyAudioSummaryAnchor {
  mediaId: string;
  groupCount: number;
}

export function selectReadyAudioSummaryAnchor(
  uploadedAudio: AudioSummaryAnchorCandidate[],
  groupCount: number,
): ReadyAudioSummaryAnchor | null {
  if (groupCount < 1 || uploadedAudio.length < groupCount) {
    return null;
  }

  const firstAudio = uploadedAudio
    .slice()
    .sort((lhs, rhs) => {
      if (lhs.sortOrder === rhs.sortOrder) {
        return lhs.id.localeCompare(rhs.id);
      }

      return lhs.sortOrder - rhs.sortOrder;
    })
    .at(0);

  return firstAudio ? { mediaId: firstAudio.id, groupCount } : null;
}
