# Contributing to Azure Amortized Cost Management

Thank you for your interest in contributing! This project welcomes contributions and suggestions.

## How to Contribute

### Reporting Issues
- Use [GitHub Issues](../../issues) to report bugs or request features
- Search existing issues before creating a new one
- Include steps to reproduce, expected vs actual behavior, and your environment details

### Pull Requests
1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `python -m pytest tests/function/ -v`
5. Validate Bicep: `az bicep build --file infra/main.bicep`
6. Commit with a descriptive message
7. Push and open a Pull Request

### Code Standards
- **Python:** Follow PEP 8. Use type hints where practical.
- **Bicep:** Follow Azure Well-Architected naming conventions. Tag all resources.
- **PowerShell:** Use `Set-StrictMode -Version Latest`. Support `-WhatIf` for destructive operations.
- **Tests:** Add tests for new Function App endpoints. Maintain 100% pass rate.

### What We Accept
- Bug fixes
- New Bicep modules for additional Azure services
- Additional dashboard templates (Grafana, Power BI)
- CI/CD pipeline templates (GitHub Actions, Azure Pipelines, GitLab CI)
- Documentation improvements
- Localization / multi-currency support

### What We Don't Accept
- Customer-specific configurations (keep it generic)
- Hardcoded secrets, subscription IDs, or tenant IDs
- Features that break the per-subscription deployment model

## Code of Conduct

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
