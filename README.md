# Sahmi Picks Mobile — قوايم الأسهم اليومية

Offline Arabic Flutter app: daily EGX stock pick lists (intraday / swing / 5-day /
investment / consensus), horizon search, and trade record — for EGX33 and all EGX stocks.

- Data is **bundled** under `assets/data/` (exported from the desktop pipeline).
- No internet permission: 100% offline.
- APK is built on GitHub Actions (no local Android SDK needed).

## Update data + rebuild

```powershell
python ..\export_mobile_data.py   # refresh assets from latest picks
git add -A; git commit -m "data update"; git push
```

Push to `main` rebuilds the APK (Actions → Artifacts).
Push a tag `v1.0.1` creates a GitHub Release with the APK attached.
