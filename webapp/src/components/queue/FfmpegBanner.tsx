import type { FfmpegProgress } from '../../api/queue'

export function FfmpegBanner({ progress }: { progress: FfmpegProgress }) {
  return (
    <div className="ffmpeg-banner">
      <div className="ffmpeg-banner__bar">
        <div className="ffmpeg-banner__fill" style={{ width: `${progress.percent}%` }} />
      </div>
      <div className="ffmpeg-banner__stats text-body-md">
        <span>{progress.percent.toFixed(1)}%</span>
        <span>{progress.time}</span>
        <span>{progress.speed}</span>
        <span>{progress.bandwidth}</span>
      </div>
    </div>
  )
}
