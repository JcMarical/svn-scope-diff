type CloseEvent = { preventDefault(): void };
type CloseListener = (handler: (event: CloseEvent) => void) => Promise<() => void>;

// 无草稿时保留原生关闭路径，扫描或前端通信未返回也不应拦住关闭
export function listenForDraftClose(
  hasDraft: boolean,
  listen: CloseListener,
  discard: () => boolean,
  onError: (error: unknown) => void,
) {
  let active = true;
  let stop: (() => void) | undefined;
  if (hasDraft) {
    void listen((event) => {
      if (!discard()) event.preventDefault();
    }).then((unlisten) => {
      if (active) stop = unlisten;
      else unlisten();
    }).catch(onError);
  }
  return () => { active = false; stop?.(); };
}
