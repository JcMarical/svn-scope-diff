// 只限制读取结果的等待时间，不重试写入，也不把迟到结果当作当前扫描结果
export function withReadTimeout<T>(task: Promise<T>, timeout: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), timeout);
    task.then(resolve, reject).finally(() => clearTimeout(timer));
  });
}
