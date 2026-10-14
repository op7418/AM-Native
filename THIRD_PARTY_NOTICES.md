# Third-party notices / 第三方说明

The MIT license applies to the project's own source and documentation. It does not grant rights to third-party product photographs, trademarks or brand names.

MIT 许可证适用于本项目自身代码与文档，不包含第三方产品照片、商标和品牌名称的授权。

## Angry Miao mouse illustrations

The UI references black and white product illustrations published by Angry Miao. They are not included in this source repository. `scripts/fetch-artwork.sh` fetches them directly from the original HTTPS URLs and checks these hashes:

| File | SHA-256 | Source |
| --- | --- | --- |
| `am-infinity.png` | `1a1c41f5ed8290526cae2951972713982e63382a97bc1d7a4cf8d1dc733e680f` | [Official white illustration](https://ammaster.angrymiao.com/mouse/assets/device_am35_m_a-1a1c41f5.png) |
| `am-infinity-black.png` | `90679245da81bab3db731f450e7aa58a4c841542c8e194c707d261d84ba242f9` | [Official black illustration](https://ammaster.angrymiao.com/mouse/assets/device_am35_m_b-90679245.png) |

Images and Angry Miao / AM Infinity names belong to their respective rights holders. No open-source license for the images is asserted. Preview app bundles and UI screenshots may display those images; this does not place them under MIT. The release icon was AI-generated using a device reference; it does not transfer rights to third-party branding. The fallback icon drawing code is part of this project's MIT-licensed source.

产品图片与名称归相应权利人所有，本项目不宣称图片具有开放许可。预览 App 和界面截图中展示这些图片，不表示将其重新以 MIT 授权。发布版图标由 AI 参考设备图片生成，不转移第三方品牌权利；备用图标的绘制代码属于本项目 MIT 源码。

## Protocol implementation

The HID implementation is independently written in Swift for interoperability. Official JavaScript, Python runtimes and firmware are not embedded in the source repository. Official update checks read public vendor endpoints; the app does not install or flash firmware.
