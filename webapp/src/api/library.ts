import { apiFetch } from './client'

export interface LibraryEpisodeFile {
  episode: number
  file: string
  size: number
  is_video: boolean
}

export interface LibraryTitle {
  folder: string
  seasons: Record<string, LibraryEpisodeFile[]>
  total_episodes: number
  total_size: number
}

export interface LibraryLocation {
  label: string
  custom_path_id: number | null
  lang_folders: string[] | null
  titles: LibraryTitle[]
}

export interface LibraryResult {
  lang_sep: boolean
  locations: LibraryLocation[]
}

export function getLibrary(): Promise<LibraryResult> {
  return apiFetch<LibraryResult>('/api/library')
}

/** Port of detail_screen.dart's folder-matching logic — finds a title in the
 * library whose folder name matches the series and that has the requested
 * episode's video file already downloaded. */
export function findDownloadedFolder(
  library: LibraryResult,
  seriesTitle: string,
  season: number,
  episode: number,
): string | null {
  const needle = seriesTitle.trim().toLowerCase()
  for (const location of library.locations) {
    for (const title of location.titles) {
      if (!title.folder.toLowerCase().startsWith(needle)) continue
      const files = title.seasons[String(season)]
      if (files?.some((f) => f.episode === episode && f.is_video)) return title.folder
    }
  }
  return null
}

export interface DeleteFromLibraryInput {
  folder: string
  season?: number
  episode?: number
  custom_path_id?: number | null
  lang_folder?: string | null
}

export function deleteFromLibrary(input: DeleteFromLibraryInput): Promise<{ ok: boolean; deleted: number }> {
  return apiFetch('/api/library/delete', { method: 'POST', body: input })
}

export interface StorageRoot {
  label: string
  custom_path_id: number | null
  path: string
  downloads_bytes: number
  disk_total_bytes: number
  disk_used_bytes: number
  disk_free_bytes: number
}

export interface StorageStats {
  roots: StorageRoot[]
  total_downloads_bytes: number
}

export function getStorageStats(): Promise<StorageStats> {
  return apiFetch<StorageStats>('/api/storage-stats')
}
