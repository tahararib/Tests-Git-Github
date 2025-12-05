#!/bin/bash 
# FinOps Git Repository Monitoring Script updated
# Tracks repository costs and optimization opportunities
echo "=== Git FinOps Analysis ==="
echo "Date: $(date)"
echo ""

# Repository size analysis
echo "Repository Size Analysis:"
git count-objects -vH

# Large files detection
echo ""
echo "Large Files (>10MB):"
git rev-list --objects --all | 
git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' |
sed -n 's/^blob //p' |
sort --numeric-sort --key=2 |
tail -10

# Branch analysis
echo ""
echo "Branch Analysis:"
echo "Active branches: $(git branch -r | wc -l)"
echo "Stale branches (>30 days):"
git for-each-ref --format='%(refname:short) %(committerdate)' refs/remotes |
awk '$2 < "'$(date -d '30 days ago' '+%Y-%m-%d')'"' | head -5

# CI/CD cost estimation
echo ""
echo "CI/CD Impact:"
COMMITS_LAST_MONTH=$(git rev-list --count --since="1 month ago" HEAD)
echo "Commits last month: $COMMITS_LAST_MONTH"
echo "Estimated CI runs: $COMMITS_LAST_MONTH"
echo "Estimated monthly CI cost: \$$(echo "$COMMITS_LAST_MONTH * 0.05" | bc)"

# Storage optimization recommendations
echo ""
echo "Optimization Recommendations:"
LFS_CANDIDATES=$(find . -type f -size +50M 2>/dev/null | wc -l)
if [ $LFS_CANDIDATES -gt 0 ]; then
    echo "- Consider Git LFS for $LFS_CANDIDATES large files"
fi

REPO_SIZE_MB=$(git count-objects -vH | grep size-pack | awk '{print $2}' | sed 's/M//')
if [ "${REPO_SIZE_MB:-0}" -gt 100 ]; then
    echo "- Repository size (${REPO_SIZE_MB}MB) suggests cleanup needed"
fi
