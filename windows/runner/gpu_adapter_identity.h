#ifndef KLPBBS_GPU_ADAPTER_IDENTITY_H_
#define KLPBBS_GPU_ADAPTER_IDENTITY_H_
#include <windows.h>
#include <d3dkmthk.h>
#include <algorithm>
#include <cwctype>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

namespace klpbbs_gpu {
// Display drivers can expose several logical adapters for one physical GPU.
// Query kernel PnP identities; names must not collapse same-model cards.
inline std::wstring PhysicalIdentity(const LUID& luid) {
  const HMODULE gdi = ::GetModuleHandleW(L"gdi32.dll");
  if (!gdi) return {};
  const auto open = reinterpret_cast<PFND3DKMT_OPENADAPTERFROMLUID>(
      ::GetProcAddress(gdi, "D3DKMTOpenAdapterFromLuid"));
  const auto query = reinterpret_cast<PFND3DKMT_QUERYADAPTERINFO>(
      ::GetProcAddress(gdi, "D3DKMTQueryAdapterInfo"));
  const auto close = reinterpret_cast<PFND3DKMT_CLOSEADAPTER>(
      ::GetProcAddress(gdi, "D3DKMTCloseAdapter"));
  if (!open || !query || !close) return {};
  D3DKMT_OPENADAPTERFROMLUID opened = {};
  opened.AdapterLuid = luid;
  if (open(&opened) < 0) return {};
  struct CloseAdapter {
    D3DKMT_HANDLE handle;
    PFND3DKMT_CLOSEADAPTER close;
    ~CloseAdapter() {
      D3DKMT_CLOSEADAPTER value = {handle};
      close(&value);
    }
  } cleanup{opened.hAdapter, close};
  D3DKMT_PHYSICAL_ADAPTER_COUNT physical_count = {};
  D3DKMT_QUERYADAPTERINFO count_query = {};
  count_query.hAdapter = opened.hAdapter;
  count_query.Type = KMTQAITYPE_PHYSICALADAPTERCOUNT;
  count_query.pPrivateDriverData = &physical_count;
  count_query.PrivateDriverDataSize = sizeof(physical_count);
  if (query(&count_query) < 0 || physical_count.Count == 0 ||
      physical_count.Count > 32) return {};
  std::vector<std::wstring> keys;
  for (UINT index = 0; index < physical_count.Count; ++index) {
    wchar_t path[1024] = {};
    UINT capacity = static_cast<UINT>(std::size(path));
    D3DKMT_QUERY_PHYSICAL_ADAPTER_PNP_KEY key = {};
    key.PhysicalAdapterIndex = index;
    key.PnPKeyType = D3DKMT_PNP_KEY_HARDWARE;
    key.pDest = path;
    key.pCchDest = &capacity;
    D3DKMT_QUERYADAPTERINFO request = {};
    request.hAdapter = opened.hAdapter;
    request.Type = KMTQAITYPE_PHYSICALADAPTERPNPKEY;
    request.pPrivateDriverData = &key;
    request.PrivateDriverDataSize = sizeof(key);
    if (query(&request) < 0 || !path[0] || capacity > std::size(path)) return {};
    path[std::size(path) - 1] = L'\0';
    std::wstring identity(path);
    std::transform(identity.begin(), identity.end(), identity.begin(),
                   [](wchar_t character) { return std::towupper(character); });
    keys.push_back(std::move(identity));
  }
  // An entire linked-adapter chain is one DXGI adapter, not a single member.
  std::sort(keys.begin(), keys.end());
  std::wstring identity;
  for (const auto& key : keys) identity += std::to_wstring(key.size()) + L":" + key;
  return identity;
}

}  // namespace klpbbs_gpu
#endif
